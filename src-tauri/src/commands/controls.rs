// Controls test: runs controls_test.sh on the host and forwards each JSON line
// it prints to the frontend as a "controls-test" event while the test is open.

use std::process::Child;
use std::sync::Mutex;
use tauri::{AppHandle, Manager};

pub struct ControlsTest(pub Mutex<Option<Child>>);

#[tauri::command]
pub fn start_controls_test(app: AppHandle) -> Result<(), String> {
    stop_child(&app);
    start_child(&app)
}

#[tauri::command]
pub fn stop_controls_test(app: AppHandle) {
    stop_child(&app);
}

#[cfg(target_os = "linux")]
fn start_child(app: &AppHandle) -> Result<(), String> {
    use std::io::{BufRead, BufReader};
    use std::process::Stdio;
    use tauri::Emitter;

    let script = super::scripts::prepare_host_script(app, "controls_test.sh")?;
    let mut child = super::scripts::host_command("bash")
        .arg(&script)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| format!("spawn controls test: {}", e))?;

    let stdout = child.stdout.take().ok_or("controls test has no output")?;
    *app.state::<ControlsTest>().0.lock().unwrap() = Some(child);

    let app = app.clone();
    std::thread::spawn(move || {
        for line in BufReader::new(stdout).lines().map_while(Result::ok) {
            let _ = app.emit("controls-test", line);
        }
        let _ = app.emit("controls-test", r#"{"type":"end"}"#.to_string());
    });
    Ok(())
}

#[cfg(not(target_os = "linux"))]
fn start_child(_app: &AppHandle) -> Result<(), String> {
    Err("The controls test only works when Deck Toolbox runs on the Deck.".into())
}

fn stop_child(app: &AppHandle) {
    if let Some(mut child) = app.state::<ControlsTest>().0.lock().unwrap().take() {
        // Closing stdin tells the script to exit
        drop(child.stdin.take());
        let _ = child.kill();
        let _ = child.wait();
    }
}
