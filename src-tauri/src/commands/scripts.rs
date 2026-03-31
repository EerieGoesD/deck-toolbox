use std::io::Write;
use std::process::{Command, Stdio};
use std::sync::Mutex;
use tauri::AppHandle;
use tauri::Manager;

/// Stores the sudo password so scripts can use it
pub struct SudoPassword(pub Mutex<Option<String>>);

#[derive(serde::Serialize)]
pub struct ScriptResult {
    pub code: i32,
    pub stdout: String,
    pub stderr: String,
}

fn scripts_dir(app: &AppHandle) -> std::path::PathBuf {
    app.path()
        .resource_dir()
        .expect("failed to resolve resource dir")
        .join("resources")
        .join("scripts")
}

fn run_script_internal(
    app: &AppHandle,
    script_name: &str,
    args: &[&str],
) -> Result<ScriptResult, String> {
    let script_path = scripts_dir(app).join(script_name);
    let home = dirs::home_dir().ok_or("Cannot find home directory")?;

    // Ensure script is executable (Linux/macOS only)
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        if let Ok(metadata) = std::fs::metadata(&script_path) {
            let mut perms = metadata.permissions();
            perms.set_mode(0o755);
            let _ = std::fs::set_permissions(&script_path, perms);
        }
    }

    // Check if we have a stored sudo password
    let sudo_password = app
        .state::<SudoPassword>()
        .0
        .lock()
        .unwrap()
        .clone();

    // Build a wrapper script that caches sudo first if password is available
    let script_str = script_path.to_string_lossy().to_string();
    let args_str: Vec<String> = args.iter().map(|a| format!("\"{}\"", a)).collect();
    let args_joined = args_str.join(" ");

    let wrapper = if let Some(ref pw) = sudo_password {
        // Pipe password to sudo -S -v to cache credentials in this bash session,
        // then run the actual script
        format!(
            "echo '{}' | sudo -S -v 2>/dev/null; bash \"{}\" {}",
            pw.replace('\'', "'\\''"),
            script_str,
            args_joined
        )
    } else {
        format!("bash \"{}\" {}", script_str, args_joined)
    };

    let output = Command::new("bash")
        .args(["-c", &wrapper])
        .env("HOME", &home)
        .current_dir(&home)
        .output()
        .map_err(|e| e.to_string())?;

    Ok(ScriptResult {
        code: output.status.code().unwrap_or(-1),
        stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
    })
}

#[tauri::command]
pub async fn cache_sudo(app: AppHandle, password: String) -> Result<ScriptResult, String> {
    let pw = password.clone();
    let result = tauri::async_runtime::spawn_blocking(move || {
        let mut child = Command::new("sudo")
            .args(["-S", "-v"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| e.to_string())?;

        if let Some(mut stdin) = child.stdin.take() {
            let _ = writeln!(stdin, "{}", pw);
        }

        let output = child.wait_with_output().map_err(|e| e.to_string())?;

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
        let mut child = Command::new("sudo")
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
pub async fn set_user_password(new_password: String) -> Result<ScriptResult, String> {
    tauri::async_runtime::spawn_blocking(move || {
        // On SteamOS, deck user has no password by default.
        // Use chpasswd which reads "user:password" from stdin
        let mut child = Command::new("sudo")
            .args(["-S", "chpasswd"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| e.to_string())?;

        if let Some(mut stdin) = child.stdin.take() {
            // First line: empty password for sudo (deck has no password by default)
            let _ = writeln!(stdin, "");
            // chpasswd expects "username:newpassword"
            let _ = writeln!(stdin, "deck:{}", new_password);
        }

        let output = child.wait_with_output().map_err(|e| e.to_string())?;

        // If that didn't work (sudo needs password), try with passwd --stdin
        if !output.status.success() {
            let mut child2 = Command::new("passwd")
                .args(["--stdin", "deck"])
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                .spawn()
                .map_err(|e| e.to_string())?;

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
pub async fn run_maintenance(app: AppHandle) -> Result<ScriptResult, String> {
    tauri::async_runtime::spawn_blocking(move || run_script_internal(&app, "maintenance.sh", &[]))
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
pub async fn find_lost_roms(app: AppHandle) -> Result<ScriptResult, String> {
    tauri::async_runtime::spawn_blocking(move || run_script_internal(&app, "find_lost_roms.sh", &[]))
        .await.map_err(|e| e.to_string())?
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
pub async fn rom_size_sorter(app: AppHandle) -> Result<ScriptResult, String> {
    tauri::async_runtime::spawn_blocking(move || run_script_internal(&app, "rom_size_sorter.sh", &[]))
        .await.map_err(|e| e.to_string())?
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
