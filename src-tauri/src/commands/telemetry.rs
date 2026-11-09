// The usage line at the left of the footer: version, and what the app itself
// is costing the Deck (CPU, RAM) plus the size of the files it keeps.

use tauri::AppHandle;

#[tauri::command]
pub fn app_version(app: AppHandle) -> String {
    app.package_info().version.to_string()
}

#[tauri::command]
pub fn usage() -> (String, String) {
    read_usage()
}

/// This process's share of the processor since the last reading, and its
/// resident memory as a share of the Deck's total memory. Read from
/// /proc/self, which inside the Flatpak is still the app's own process.
#[cfg(target_os = "linux")]
fn read_usage() -> (String, String) {
    use std::sync::Mutex;
    use std::time::Instant;

    static LAST: Mutex<Option<(u64, Instant)>> = Mutex::new(None);

    // utime and stime are fields 14 and 15 of /proc/self/stat, in clock ticks.
    // The name in field 2 can contain spaces, so count from its closing ")":
    // after it the fields start at 3, which puts utime at index 11.
    let ticks = std::fs::read_to_string("/proc/self/stat").ok().and_then(|stat| {
        let rest = &stat[stat.rfind(')')? + 1..];
        let fields: Vec<&str> = rest.split_whitespace().collect();
        let utime: u64 = fields.get(11)?.parse().ok()?;
        let stime: u64 = fields.get(12)?.parse().ok()?;
        Some(utime + stime)
    });
    let tick_hz = unsafe { libc::sysconf(libc::_SC_CLK_TCK) };
    let cores = unsafe { libc::sysconf(libc::_SC_NPROCESSORS_ONLN) }.max(1) as f64;

    let cpu = match ticks {
        Some(ticks) if tick_hz > 0 => {
            // Same unit as the macOS and iOS readings: nanoseconds.
            let busy = ticks * 1_000_000_000 / tick_hz as u64;
            let now = Instant::now();
            let mut slot = LAST.lock().unwrap();
            let share = match *slot {
                Some((was_busy, was_at)) => {
                    let elapsed = now.duration_since(was_at).as_secs_f64();
                    if elapsed <= 0.0 {
                        0.0
                    } else {
                        let spent = busy.saturating_sub(was_busy) as f64 / 1_000_000_000.0;
                        (spent / elapsed / cores * 100.0).clamp(0.0, 100.0)
                    }
                }
                None => 0.0,
            };
            *slot = Some((busy, now));
            format!("{share:.1}%")
        }
        _ => "n/a".to_string(),
    };

    // "VmRSS:   123456 kB" in /proc/self/status, "MemTotal: 15153384 kB" in
    // /proc/meminfo. Both in kB, so the units cancel.
    fn kb(file: &str, key: &str) -> Option<u64> {
        let text = std::fs::read_to_string(file).ok()?;
        let line = text.lines().find(|l| l.starts_with(key))?;
        line[key.len()..].split_whitespace().next()?.parse().ok()
    }
    let ram = match (kb("/proc/self/status", "VmRSS:"), kb("/proc/meminfo", "MemTotal:")) {
        (Some(rss), Some(total)) if rss > 0 && total > 0 => {
            format!("{:.1}%", rss as f64 / total as f64 * 100.0)
        }
        _ => "n/a".to_string(),
    };

    (cpu, ram)
}

#[cfg(not(target_os = "linux"))]
fn read_usage() -> (String, String) {
    ("n/a".to_string(), "n/a".to_string())
}

/// Bytes in the folders the app writes itself: ~/.cache/deck-toolbox (the
/// scripts copied out to run on the host) and ~/.config/deck-toolbox (the
/// remembered sudo password). The web view's own files in ~/.var/app are
/// left out, the same way the Windows apps skip EBWebView.
#[tauri::command]
pub fn cache_size() -> u64 {
    fn walk(p: &std::path::Path) -> u64 {
        let mut total = 0;
        if let Ok(entries) = std::fs::read_dir(p) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_dir() {
                    total += walk(&path);
                } else if let Ok(meta) = entry.metadata() {
                    total += meta.len();
                }
            }
        }
        total
    }
    let Some(home) = dirs::home_dir() else { return 0 };
    walk(&home.join(".cache").join("deck-toolbox")) + walk(&home.join(".config").join("deck-toolbox"))
}
