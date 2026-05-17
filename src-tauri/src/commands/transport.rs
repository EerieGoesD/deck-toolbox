// Transport layer for running scripts. On Linux this is a no-op (scripts run locally
// via bash). On Windows the app connects to the Steam Deck over SSH and runs the same
// scripts on the Deck remotely.
//
// This module owns the connection state for Windows builds and the `connect_to_deck`,
// `disconnect_deck`, `is_deck_connected`, and `get_platform` Tauri commands.

use std::sync::Mutex;

/// Returns the host OS at build time so the frontend knows which UI to show.
#[tauri::command]
pub fn get_platform() -> String {
    if cfg!(target_os = "windows") {
        "windows".to_string()
    } else if cfg!(target_os = "linux") {
        "linux".to_string()
    } else if cfg!(target_os = "macos") {
        "macos".to_string()
    } else {
        "other".to_string()
    }
}

// ── Windows-only: SSH connection state and management commands ──────────────────

#[cfg(target_os = "windows")]
#[derive(Clone)]
pub struct DeckCredentials {
    pub ip: String,
    pub password: String,
}

#[cfg(target_os = "windows")]
pub struct DeckConnection(pub Mutex<Option<DeckCredentials>>);

// Linux still gets the type so state registration in lib.rs compiles without cfg gates.
#[cfg(not(target_os = "windows"))]
pub struct DeckConnection(pub Mutex<()>);

#[cfg(target_os = "windows")]
pub fn create_session(ip: &str, password: &str) -> Result<ssh2::Session, String> {
    use std::io::Read;
    use std::net::TcpStream;
    use std::time::Duration;

    let addr = format!("{}:22", ip);
    let tcp = TcpStream::connect_timeout(
        &addr.parse().map_err(|e: std::net::AddrParseError| format!("bad address {}: {}", addr, e))?,
        Duration::from_secs(8),
    )
    .map_err(|e| format!("TCP connect to {}: {}", addr, e))?;
    tcp.set_read_timeout(Some(Duration::from_secs(60))).ok();
    tcp.set_write_timeout(Some(Duration::from_secs(60))).ok();

    let mut session = ssh2::Session::new().map_err(|e| format!("ssh session new: {}", e))?;
    session.set_tcp_stream(tcp);
    session.handshake().map_err(|e| format!("ssh handshake: {}", e))?;
    session
        .userauth_password("deck", password)
        .map_err(|e| format!("ssh auth as deck@{}: {}", ip, e))?;
    if !session.authenticated() {
        return Err("ssh authentication did not complete".into());
    }
    // Touch the channel to make sure we can actually run commands.
    let mut ch = session.channel_session().map_err(|e| format!("ssh channel: {}", e))?;
    ch.exec("true").map_err(|e| format!("ssh exec test: {}", e))?;
    let mut _buf = String::new();
    let _ = ch.read_to_string(&mut _buf);
    let _ = ch.wait_close();
    Ok(session)
}

/// Tests a connection to the Deck and stores the credentials for later script execution.
/// Only available on Windows builds. On Linux this command is not registered.
#[cfg(target_os = "windows")]
#[tauri::command]
pub fn connect_to_deck(
    state: tauri::State<DeckConnection>,
    ip: String,
    password: String,
) -> Result<(), String> {
    // Smoke-test the credentials by opening a session and immediately dropping it.
    let _ = create_session(&ip, &password)?;
    let mut guard = state.0.lock().unwrap();
    *guard = Some(DeckCredentials { ip, password });
    Ok(())
}

#[cfg(target_os = "windows")]
#[tauri::command]
pub fn disconnect_deck(state: tauri::State<DeckConnection>) -> Result<(), String> {
    let mut guard = state.0.lock().unwrap();
    *guard = None;
    Ok(())
}

#[cfg(target_os = "windows")]
#[tauri::command]
pub fn is_deck_connected(state: tauri::State<DeckConnection>) -> bool {
    state.0.lock().unwrap().is_some()
}

#[cfg(target_os = "windows")]
pub fn current_credentials(state: &tauri::State<DeckConnection>) -> Result<DeckCredentials, String> {
    let guard = state.0.lock().unwrap();
    guard
        .clone()
        .ok_or_else(|| "Not connected to a Steam Deck. Use the Connect screen first.".to_string())
}

// ── Linux stubs ─────────────────────────────────────────────────────────────────
// On Linux these commands are not meaningful (the app runs on the Deck directly),
// but they need to exist as compilable symbols so lib.rs can register the same
// invoke_handler list on both targets.

#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub fn connect_to_deck(
    _state: tauri::State<DeckConnection>,
    _ip: String,
    _password: String,
) -> Result<(), String> {
    Err("connect_to_deck is only used in the Windows build of deck-toolbox.".into())
}

#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub fn disconnect_deck(_state: tauri::State<DeckConnection>) -> Result<(), String> {
    Err("disconnect_deck is only used in the Windows build of deck-toolbox.".into())
}

#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub fn is_deck_connected(_state: tauri::State<DeckConnection>) -> bool {
    // Running locally on the Deck: always "connected" to itself.
    true
}
