use std::process::Command;

#[derive(serde::Serialize)]
pub struct DiskInfo {
    pub kind: String,
    pub mount: String,
    pub label: String,
    pub total: u64,
    pub used: u64,
}

#[tauri::command]
pub async fn get_disk_usage() -> Result<Vec<DiskInfo>, String> {
    let result = tauri::async_runtime::spawn_blocking(|| -> Vec<DiskInfo> {
        let mut disks: Vec<DiskInfo> = Vec::new();

        if let Some(d) = read_disk("/home", "internal", "Internal Storage") {
            disks.push(d);
        } else if let Some(d) = read_disk("/", "internal", "Internal Storage") {
            disks.push(d);
        }

        if let Some(sd) = find_sd_card() {
            disks.push(sd);
        }

        disks
    })
    .await
    .map_err(|e| e.to_string())?;

    Ok(result)
}

fn read_disk(path: &str, kind: &str, label: &str) -> Option<DiskInfo> {
    let output = Command::new("df")
        .args(["-B1", "--output=target,size,used", path])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let stdout = String::from_utf8_lossy(&output.stdout);
    for line in stdout.lines().skip(1) {
        let fields: Vec<&str> = line.split_whitespace().collect();
        if fields.len() >= 3 {
            let target = fields[0].to_string();
            let total: u64 = fields[1].parse().ok()?;
            let used: u64 = fields[2].parse().ok()?;
            return Some(DiskInfo {
                kind: kind.to_string(),
                mount: target,
                label: label.to_string(),
                total,
                used,
            });
        }
    }
    None
}

#[cfg(unix)]
fn is_mountpoint(p: &std::path::Path) -> bool {
    use std::os::unix::fs::MetadataExt;
    let meta = match std::fs::metadata(p) {
        Ok(m) => m,
        Err(_) => return false,
    };
    let parent = match p.parent() {
        Some(par) => par,
        None => return false,
    };
    let pmeta = match std::fs::metadata(parent) {
        Ok(m) => m,
        Err(_) => return false,
    };
    meta.dev() != pmeta.dev()
}

#[cfg(unix)]
fn find_sd_card() -> Option<DiskInfo> {
    let media_dir = std::path::Path::new("/run/media");
    if !media_dir.exists() {
        return None;
    }

    let mut candidates: Vec<std::path::PathBuf> = Vec::new();
    if let Ok(entries) = std::fs::read_dir(media_dir) {
        for e in entries.flatten() {
            let p = e.path();
            if p.is_dir() {
                candidates.push(p);
            }
        }
    }

    let mut deeper: Vec<std::path::PathBuf> = Vec::new();
    for p in &candidates {
        if let Ok(sub) = std::fs::read_dir(p) {
            for s in sub.flatten() {
                let sp = s.path();
                if sp.is_dir() {
                    deeper.push(sp);
                }
            }
        }
    }
    candidates.extend(deeper);

    for cand in candidates {
        if !is_mountpoint(&cand) {
            continue;
        }
        let label_name = cand
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_else(|| "SD Card".to_string());
        let path_str = cand.to_string_lossy().to_string();
        if let Some(d) = read_disk(&path_str, "sd", &format!("SD Card ({})", label_name)) {
            return Some(d);
        }
    }
    None
}

#[cfg(not(unix))]
fn find_sd_card() -> Option<DiskInfo> {
    None
}
