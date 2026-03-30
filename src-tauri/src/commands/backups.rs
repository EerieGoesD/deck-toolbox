use super::scripts::ScriptResult;

#[tauri::command]
pub fn delete_steam_backups() -> Result<ScriptResult, String> {
    let home = dirs::home_dir().ok_or("Cannot find home directory")?;
    let share_dir = home.join(".local").join("share");

    let entries = std::fs::read_dir(&share_dir)
        .map_err(|e| format!("Could not read directory: {}", e))?;

    let mut deleted = Vec::new();
    let mut errors = Vec::new();

    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        if name.starts_with("Steam_backup") {
            match std::fs::remove_dir_all(entry.path()) {
                Ok(_) => deleted.push(name),
                Err(e) => errors.push(format!("Failed to delete {}: {}", name, e)),
            }
        }
    }

    if deleted.is_empty() && errors.is_empty() {
        return Ok(ScriptResult {
            code: 0,
            stdout: "No backup folders found.\n".into(),
            stderr: String::new(),
        });
    }

    let stdout = if deleted.is_empty() {
        String::new()
    } else {
        format!(
            "Deleted:\n{}\n",
            deleted
                .iter()
                .map(|d| format!("  - {}", d))
                .collect::<Vec<_>>()
                .join("\n")
        )
    };

    let stderr = if errors.is_empty() {
        String::new()
    } else {
        format!("{}\n", errors.join("\n"))
    };

    Ok(ScriptResult {
        code: if errors.is_empty() { 0 } else { 1 },
        stdout,
        stderr,
    })
}
