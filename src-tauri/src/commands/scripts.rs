use std::io::Write;
use std::process::{Command, Stdio};
use tauri::AppHandle;
use tauri::Manager;

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

    let output = Command::new("bash")
        .arg(&script_path)
        .args(args)
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
pub async fn cache_sudo(password: String) -> Result<ScriptResult, String> {
    tauri::async_runtime::spawn_blocking(move || cache_sudo_sync(password))
        .await
        .map_err(|e| e.to_string())?
}

fn cache_sudo_sync(password: String) -> Result<ScriptResult, String> {
    let mut child = Command::new("sudo")
        .args(["-S", "-v"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| e.to_string())?;

    if let Some(mut stdin) = child.stdin.take() {
        let _ = writeln!(stdin, "{}", password);
    }

    let output = child.wait_with_output().map_err(|e| e.to_string())?;

    Ok(ScriptResult {
        code: output.status.code().unwrap_or(-1),
        stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
    })
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
