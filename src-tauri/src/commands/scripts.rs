use std::io::Write;
use std::process::{Command, Stdio};
use std::sync::Mutex;
use tauri::AppHandle;
use tauri::Manager;

/// Stores the sudo password so scripts can use it
pub struct SudoPassword(pub Mutex<Option<String>>);

/// Build a Command that runs on the host when we are inside a Flatpak sandbox.
/// Uses `flatpak-spawn --host` (allowed by --talk-name=org.freedesktop.Flatpak)
/// so commands like sudo, bash, passwd find a real /etc/passwd, /etc/sudoers,
/// and the user's actual SteamOS environment.
fn host_command(program: &str) -> Command {
    if std::path::Path::new("/.flatpak-info").exists() {
        let mut cmd = Command::new("flatpak-spawn");
        cmd.arg("--host").arg(program);
        cmd
    } else {
        Command::new(program)
    }
}

#[derive(serde::Serialize)]
pub struct ScriptResult {
    pub code: i32,
    pub stdout: String,
    pub stderr: String,
}

fn scripts_dir(app: &AppHandle) -> std::path::PathBuf {
    // The Flatpak manifest installs scripts to /app/share/deck-toolbox/scripts/.
    // Tauri's resource_dir does not know about that location, so probe it first.
    let flatpak_scripts = std::path::PathBuf::from("/app/share/deck-toolbox/scripts");
    if flatpak_scripts.exists() {
        return flatpak_scripts;
    }
    app.path()
        .resource_dir()
        .expect("failed to resolve resource dir")
        .join("resources")
        .join("scripts")
}

#[cfg(target_os = "linux")]
fn run_script_internal(
    app: &AppHandle,
    script_name: &str,
    args: &[&str],
) -> Result<ScriptResult, String> {
    let bundled_path = scripts_dir(app).join(script_name);
    let home = dirs::home_dir().ok_or("Cannot find home directory")?;

    // Copy the script out of the Flatpak overlay (which the host bash cannot
    // read) into the user's cache dir. ~/.cache/... is bind-mounted into the
    // sandbox, so both sides see the same file.
    let cache_dir = home.join(".cache").join("deck-toolbox").join("scripts");
    std::fs::create_dir_all(&cache_dir).map_err(|e| format!("create cache dir: {}", e))?;
    let host_path = cache_dir.join(script_name);
    std::fs::copy(&bundled_path, &host_path)
        .map_err(|e| format!("copy script {}: {}", script_name, e))?;

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(&host_path, std::fs::Permissions::from_mode(0o755));
    }

    let sudo_password = app
        .state::<SudoPassword>()
        .0
        .lock()
        .unwrap()
        .clone();

    let script_str = host_path.to_string_lossy().to_string();

    // Wrapper reads the sudo password from stdin (line 1), validates it once,
    // then replaces the `sudo` builtin in this bash session with a function
    // that strips -n and pipes the password via -S. Scripts can keep using
    // `sudo -n cmd` and they will actually authenticate. The script itself
    // gets stdin closed so it cannot consume the password line.
    let wrapper_with_sudo = r#"
read -r DT_SUDO_PASS
if ! printf '%s\n' "$DT_SUDO_PASS" | command sudo -S -v 2>/dev/null; then
    echo "Sudo authentication failed - check the password set via Unlock" >&2
    exit 64
fi
sudo() {
    local f=()
    local a
    for a in "$@"; do
        [[ "$a" != "-n" ]] && f+=("$a")
    done
    printf '%s\n' "$DT_SUDO_PASS" | command sudo -S "${f[@]}"
}
export -f sudo
bash "$1" "${@:2}" </dev/null
"#;

    let mut command = if let Some(_pw) = &sudo_password {
        let mut c = host_command("bash");
        c.arg("-c").arg(wrapper_with_sudo).arg("--").arg(&script_str);
        for a in args { c.arg(a); }
        c.stdin(Stdio::piped());
        c
    } else {
        let mut c = host_command("bash");
        c.arg(&script_str);
        for a in args { c.arg(a); }
        c
    };
    command.stdout(Stdio::piped()).stderr(Stdio::piped());

    let mut child = command.spawn().map_err(|e| format!("spawn bash: {}", e))?;

    if let (Some(pw), Some(mut stdin)) = (sudo_password.as_ref(), child.stdin.take()) {
        let _ = writeln!(stdin, "{}", pw);
    }

    let output = child.wait_with_output().map_err(|e| format!("wait bash: {}", e))?;

    Ok(ScriptResult {
        code: output.status.code().unwrap_or(-1),
        stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
    })
}

/// Windows path: connect to the Steam Deck over SSH, upload the bundled script to
/// ~/.cache/deck-toolbox/scripts/ on the Deck, then exec it via bash. Captures stdout,
/// stderr and the exit code the same way the Linux path does so the JS frontend does
/// not need to care which build it is.
#[cfg(target_os = "windows")]
fn run_script_internal(
    app: &AppHandle,
    script_name: &str,
    args: &[&str],
) -> Result<ScriptResult, String> {
    use crate::commands::transport::{create_session, current_credentials, DeckConnection};
    use std::io::{Read as IoRead, Write as IoWrite};

    let creds = current_credentials(&app.state::<DeckConnection>())?;

    // Read the script content from the bundled resources on the host.
    let bundled_path = scripts_dir(app).join(script_name);
    let script_bytes = std::fs::read(&bundled_path)
        .map_err(|e| format!("read bundled script {}: {}", script_name, e))?;

    let session = create_session(&creds.ip, &creds.password)?;

    // Make sure ~/.cache/deck-toolbox/scripts/ exists on the Deck.
    let remote_dir = "/home/deck/.cache/deck-toolbox/scripts";
    {
        let mut ch = session
            .channel_session()
            .map_err(|e| format!("ssh channel (mkdir): {}", e))?;
        ch.exec(&format!("mkdir -p '{}'", remote_dir))
            .map_err(|e| format!("mkdir exec: {}", e))?;
        let mut buf = String::new();
        let _ = ch.read_to_string(&mut buf);
        let _ = ch.wait_close();
    }

    // Upload the script via SCP (simpler than SFTP for one file).
    let remote_path = format!("{}/{}", remote_dir, script_name);
    {
        let mut remote = session
            .scp_send(
                std::path::Path::new(&remote_path),
                0o755,
                script_bytes.len() as u64,
                None,
            )
            .map_err(|e| format!("scp_send {}: {}", remote_path, e))?;
        remote
            .write_all(&script_bytes)
            .map_err(|e| format!("scp write: {}", e))?;
        remote.send_eof().ok();
        remote.wait_eof().ok();
        remote.close().ok();
        remote.wait_close().ok();
    }

    // Quote each script argument for bash (single-quote, escape any embedded ').
    fn q(s: &str) -> String {
        format!("'{}'", s.replace('\'', "'\\''"))
    }
    let quoted_args: Vec<String> = args.iter().map(|a| q(a)).collect();
    let cmd = format!("bash {} {}", q(&remote_path), quoted_args.join(" "));

    let mut channel = session
        .channel_session()
        .map_err(|e| format!("ssh channel (exec): {}", e))?;
    channel.exec(&cmd).map_err(|e| format!("ssh exec: {}", e))?;

    let mut stdout = String::new();
    channel
        .read_to_string(&mut stdout)
        .map_err(|e| format!("read stdout: {}", e))?;
    let mut stderr = String::new();
    let _ = channel.stderr().read_to_string(&mut stderr);
    channel.wait_close().ok();
    let code = channel.exit_status().unwrap_or(-1);

    Ok(ScriptResult { code, stdout, stderr })
}

#[tauri::command]
pub async fn cache_sudo(app: AppHandle, password: String) -> Result<ScriptResult, String> {
    let pw = password.clone();
    let result = tauri::async_runtime::spawn_blocking(move || {
        let mut child = host_command("sudo")
            .args(["-S", "-v"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| format!("spawn sudo: {}", e))?;

        if let Some(mut stdin) = child.stdin.take() {
            let _ = writeln!(stdin, "{}", pw);
        }

        let output = child.wait_with_output().map_err(|e| format!("sudo wait: {}", e))?;

        Ok::<ScriptResult, String>(ScriptResult {
            code: output.status.code().unwrap_or(-1),
            stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
        })
    })
    .await
    .map_err(|e| e.to_string())??;

    // If sudo succeeded, store the password for scripts to use
    if result.code == 0 {
        let state = app.state::<SudoPassword>();
        let mut stored = state.0.lock().unwrap();
        *stored = Some(password);
    }

    Ok(result)
}

#[tauri::command]
pub async fn export_log(app: AppHandle, content: String) -> Result<String, String> {
    use tauri_plugin_dialog::DialogExt;

    let file_path = app
        .dialog()
        .file()
        .add_filter("Text files", &["txt", "log"])
        .set_file_name("deck-toolbox-log.txt")
        .blocking_save_file();

    match file_path {
        Some(path) => {
            let p = path.into_path().map_err(|e| e.to_string())?;
            std::fs::write(&p, &content).map_err(|e| e.to_string())?;
            Ok(p.to_string_lossy().to_string())
        }
        None => Ok("cancelled".into()),
    }
}

fn password_file() -> Result<std::path::PathBuf, String> {
    let home = dirs::home_dir().ok_or("Cannot find home directory")?;
    let dir = home.join(".config").join("deck-toolbox");
    let _ = std::fs::create_dir_all(&dir);
    Ok(dir.join(".credentials"))
}

#[tauri::command]
pub async fn save_sudo_password(app: AppHandle, password: String) -> Result<(), String> {
    use std::io::Write as _;
    let path = password_file()?;
    let encoded = base64_encode(&password);
    let mut f = std::fs::File::create(&path).map_err(|e| e.to_string())?;
    f.write_all(encoded.as_bytes()).map_err(|e| e.to_string())?;

    // Also set restrictive permissions
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600));
    }

    // Store in memory too
    let state = app.state::<SudoPassword>();
    let mut stored = state.0.lock().unwrap();
    *stored = Some(password);

    Ok(())
}

#[tauri::command]
pub async fn load_sudo_password(app: AppHandle) -> Result<String, String> {
    let path = password_file()?;
    if !path.exists() {
        return Ok(String::new());
    }
    let encoded = std::fs::read_to_string(&path).map_err(|e| e.to_string())?;
    let password = base64_decode(&encoded)?;

    // Validate it still works
    let pw = password.clone();
    let valid = tauri::async_runtime::spawn_blocking(move || {
        let mut child = host_command("sudo")
            .args(["-S", "-v"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .ok()?;
        if let Some(mut stdin) = child.stdin.take() {
            let _ = writeln!(stdin, "{}", pw);
        }
        let output = child.wait_with_output().ok()?;
        Some(output.status.success())
    }).await.map_err(|e| e.to_string())?;

    if valid == Some(true) {
        let state = app.state::<SudoPassword>();
        let mut stored = state.0.lock().unwrap();
        *stored = Some(password.clone());
        Ok(password)
    } else {
        // Password no longer valid, delete saved file
        let _ = std::fs::remove_file(&path);
        Ok(String::new())
    }
}

#[tauri::command]
pub async fn clear_sudo_password() -> Result<(), String> {
    let path = password_file()?;
    let _ = std::fs::remove_file(&path);
    Ok(())
}

fn base64_encode(s: &str) -> String {
    const CHARS: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let bytes = s.as_bytes();
    let mut result = String::new();
    for chunk in bytes.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = if chunk.len() > 1 { chunk[1] as u32 } else { 0 };
        let b2 = if chunk.len() > 2 { chunk[2] as u32 } else { 0 };
        let triple = (b0 << 16) | (b1 << 8) | b2;
        result.push(CHARS[((triple >> 18) & 0x3F) as usize] as char);
        result.push(CHARS[((triple >> 12) & 0x3F) as usize] as char);
        if chunk.len() > 1 { result.push(CHARS[((triple >> 6) & 0x3F) as usize] as char); } else { result.push('='); }
        if chunk.len() > 2 { result.push(CHARS[(triple & 0x3F) as usize] as char); } else { result.push('='); }
    }
    result
}

fn base64_decode(s: &str) -> Result<String, String> {
    let s = s.trim();
    let mut bytes = Vec::new();
    let chars: Vec<u8> = s.bytes().collect();
    for chunk in chars.chunks(4) {
        if chunk.len() < 4 { break; }
        let vals: Vec<u32> = chunk.iter().map(|&c| {
            match c {
                b'A'..=b'Z' => (c - b'A') as u32,
                b'a'..=b'z' => (c - b'a' + 26) as u32,
                b'0'..=b'9' => (c - b'0' + 52) as u32,
                b'+' => 62, b'/' => 63, _ => 0,
            }
        }).collect();
        let triple = (vals[0] << 18) | (vals[1] << 12) | (vals[2] << 6) | vals[3];
        bytes.push(((triple >> 16) & 0xFF) as u8);
        if chunk[2] != b'=' { bytes.push(((triple >> 8) & 0xFF) as u8); }
        if chunk[3] != b'=' { bytes.push((triple & 0xFF) as u8); }
    }
    String::from_utf8(bytes).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn check_has_password() -> Result<bool, String> {
    // Try sudo -n true - if it works, password is cached or NOPASSWD.
    // Try sudo -S true with empty password - if it works, no password is set.
    let result = tauri::async_runtime::spawn_blocking(|| {
        let mut child = host_command("sudo")
            .args(["-S", "true"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .ok()?;
        if let Some(mut stdin) = child.stdin.take() {
            // Send empty password
            let _ = writeln!(stdin, "");
        }
        let output = child.wait_with_output().ok()?;
        // If empty password works, user has NO password set
        // If it fails, user HAS a password set
        Some(!output.status.success())
    })
    .await
    .map_err(|e| e.to_string())?;

    Ok(result.unwrap_or(true))
}

#[tauri::command]
pub async fn set_user_password(new_password: String) -> Result<ScriptResult, String> {
    tauri::async_runtime::spawn_blocking(move || {
        // On SteamOS, deck user has no password by default.
        // Use chpasswd which reads "user:password" from stdin
        let mut child = host_command("sudo")
            .args(["-S", "chpasswd"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| format!("spawn sudo chpasswd: {}", e))?;

        if let Some(mut stdin) = child.stdin.take() {
            // First line: empty password for sudo (deck has no password by default)
            let _ = writeln!(stdin, "");
            // chpasswd expects "username:newpassword"
            let _ = writeln!(stdin, "deck:{}", new_password);
        }

        let output = child.wait_with_output().map_err(|e| e.to_string())?;

        // If that didn't work (sudo needs password), try with passwd --stdin
        if !output.status.success() {
            let mut child2 = host_command("passwd")
                .args(["--stdin", "deck"])
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                .spawn()
                .map_err(|e| format!("spawn passwd: {}", e))?;

            if let Some(mut stdin) = child2.stdin.take() {
                let _ = writeln!(stdin, "{}", new_password);
            }

            let output2 = child2.wait_with_output().map_err(|e| e.to_string())?;
            return Ok(ScriptResult {
                code: output2.status.code().unwrap_or(-1),
                stdout: String::from_utf8_lossy(&output2.stdout).into_owned(),
                stderr: String::from_utf8_lossy(&output2.stderr).into_owned(),
            });
        }

        Ok(ScriptResult {
            code: output.status.code().unwrap_or(-1),
            stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
        })
    }).await.map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn delete_files(files: Vec<String>) -> Result<ScriptResult, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let mut trashed = Vec::new();
        let mut errors = Vec::new();

        // Use gio trash (available on SteamOS) to move files to Trash
        for f in &files {
            let output = Command::new("gio")
                .args(["trash", f])
                .output();

            match output {
                Ok(o) if o.status.success() => {
                    trashed.push(format!("Trashed: {}", f));
                }
                Ok(o) => {
                    let err = String::from_utf8_lossy(&o.stderr).trim().to_string();
                    errors.push(format!("Failed: {} - {}", f, err));
                }
                Err(e) => {
                    errors.push(format!("Failed: {} - {}", f, e));
                }
            }
        }

        let stdout = if trashed.is_empty() && errors.is_empty() {
            "No files selected.\n".into()
        } else {
            let mut out = String::new();
            for d in &trashed { out.push_str(&format!("{}\n", d)); }
            for e in &errors { out.push_str(&format!("{}\n", e)); }
            out.push_str(&format!("\n{} moved to Trash, {} failed.\n", trashed.len(), errors.len()));
            out
        };
        Ok(ScriptResult {
            code: if errors.is_empty() { 0 } else { 1 },
            stdout,
            stderr: String::new(),
        })
    }).await.map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn open_url(url: String) -> Result<(), String> {
    tauri::async_runtime::spawn_blocking(move || {
        #[cfg(target_os = "linux")]
        { let _ = Command::new("xdg-open").arg(&url).spawn(); }
        #[cfg(target_os = "windows")]
        { let _ = Command::new("cmd").args(["/C", "start", &url]).spawn(); }
        #[cfg(target_os = "macos")]
        { let _ = Command::new("open").arg(&url).spawn(); }
    }).await.map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
pub async fn run_maintenance(app: AppHandle, force_heavy: String) -> Result<ScriptResult, String> {
    tauri::async_runtime::spawn_blocking(move || run_script_internal(&app, "maintenance.sh", &[&force_heavy]))
        .await.map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn steam_reset(app: AppHandle) -> Result<ScriptResult, String> {
    tauri::async_runtime::spawn_blocking(move || run_script_internal(&app, "steam-reset.sh", &[]))
        .await.map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn gamescope_reset(app: AppHandle) -> Result<ScriptResult, String> {
    tauri::async_runtime::spawn_blocking(move || run_script_internal(&app, "gamescope-reset.sh", &[]))
        .await.map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn full_recovery(app: AppHandle) -> Result<ScriptResult, String> {
    tauri::async_runtime::spawn_blocking(move || run_script_internal(&app, "full-recovery.sh", &[]))
        .await.map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn duplicate_rom_finder(app: AppHandle, paths: Vec<String>) -> Result<ScriptResult, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let path_refs: Vec<&str> = paths.iter().map(|s| s.as_str()).collect();
        run_script_internal(&app, "duplicate_rom_finder.sh", &path_refs)
    }).await.map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn find_decky_leftovers(app: AppHandle) -> Result<ScriptResult, String> {
    tauri::async_runtime::spawn_blocking(move || run_script_internal(&app, "find_decky_leftovers.sh", &[]))
        .await.map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn find_lost_roms(app: AppHandle, paths: Vec<String>) -> Result<ScriptResult, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let path_refs: Vec<&str> = paths.iter().map(|s| s.as_str()).collect();
        run_script_internal(&app, "find_lost_roms.sh", &path_refs)
    }).await.map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn large_file_finder(
    app: AppHandle,
    exclude_roms: String,
    mode: String,
    count: String,
) -> Result<ScriptResult, String> {
    tauri::async_runtime::spawn_blocking(move || {
        run_script_internal(&app, "large_file_finder.sh", &[&exclude_roms, &mode, &count])
    }).await.map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn remove_roms_metadata(app: AppHandle) -> Result<ScriptResult, String> {
    tauri::async_runtime::spawn_blocking(move || run_script_internal(&app, "remove_roms_metadata.sh", &[]))
        .await.map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn rom_size_sorter(app: AppHandle, paths: Vec<String>) -> Result<ScriptResult, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let path_refs: Vec<&str> = paths.iter().map(|s| s.as_str()).collect();
        run_script_internal(&app, "rom_size_sorter.sh", &path_refs)
    }).await.map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn deck_declutter(app: AppHandle) -> Result<ScriptResult, String> {
    tauri::async_runtime::spawn_blocking(move || run_script_internal(&app, "deck_declutter.sh", &[]))
        .await.map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn uninstall_decky(app: AppHandle) -> Result<ScriptResult, String> {
    tauri::async_runtime::spawn_blocking(move || run_script_internal(&app, "uninstall_decky.sh", &[]))
        .await.map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn rom_finder(app: AppHandle, search: String, paths: Vec<String>) -> Result<ScriptResult, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let mut args: Vec<&str> = vec![search.as_str()];
        let path_refs: Vec<&str> = paths.iter().map(|s| s.as_str()).collect();
        args.extend(path_refs.iter().copied());
        run_script_internal(&app, "rom_finder.sh", &args)
    }).await.map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn cleanup_dupes(app: AppHandle, mode: String, internal_root: String, sd_root: String) -> Result<ScriptResult, String> {
    tauri::async_runtime::spawn_blocking(move || {
        run_script_internal(&app, "cleanup_dupes.sh", &[mode.as_str(), internal_root.as_str(), sd_root.as_str()])
    }).await.map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn fix_rom_paths(app: AppHandle, mode: String, paths: Vec<String>) -> Result<ScriptResult, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let mut args: Vec<&str> = vec![mode.as_str()];
        let path_refs: Vec<&str> = paths.iter().map(|s| s.as_str()).collect();
        args.extend(path_refs.iter().copied());
        run_script_internal(&app, "fix_rom_paths.sh", &args)
    }).await.map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn rebalance_roms(app: AppHandle, mode: String, internal_root: String, sd_root: String, strategy: String, threshold: String) -> Result<ScriptResult, String> {
    tauri::async_runtime::spawn_blocking(move || {
        run_script_internal(&app, "rebalance_roms.sh", &[mode.as_str(), internal_root.as_str(), sd_root.as_str(), strategy.as_str(), threshold.as_str()])
    }).await.map_err(|e| e.to_string())?
}
