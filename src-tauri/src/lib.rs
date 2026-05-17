mod commands;

use std::sync::Mutex;

pub fn run() {
    #[cfg(target_os = "windows")]
    let deck_connection = commands::transport::DeckConnection(Mutex::new(None));
    #[cfg(not(target_os = "windows"))]
    let deck_connection = commands::transport::DeckConnection(Mutex::new(()));

    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(commands::scripts::SudoPassword(Mutex::new(None)))
        .manage(deck_connection)
        .invoke_handler(tauri::generate_handler![
            commands::transport::get_platform,
            commands::transport::connect_to_deck,
            commands::transport::disconnect_deck,
            commands::transport::is_deck_connected,
            commands::scripts::cache_sudo,
            commands::scripts::save_sudo_password,
            commands::scripts::load_sudo_password,
            commands::scripts::clear_sudo_password,
            commands::scripts::export_log,
            commands::scripts::check_has_password,
            commands::scripts::delete_files,
            commands::scripts::set_user_password,
            commands::scripts::open_url,
            commands::cue::generate_cue,
            commands::scripts::run_maintenance,
            commands::scripts::steam_reset,
            commands::scripts::gamescope_reset,
            commands::scripts::full_recovery,
            commands::scripts::duplicate_rom_finder,
            commands::scripts::find_decky_leftovers,
            commands::scripts::find_lost_roms,
            commands::scripts::large_file_finder,
            commands::scripts::remove_roms_metadata,
            commands::scripts::rom_size_sorter,
            commands::scripts::deck_declutter,
            commands::scripts::uninstall_decky,
            commands::scripts::rom_finder,
            commands::scripts::cleanup_dupes,
            commands::scripts::fix_rom_paths,
            commands::scripts::rebalance_roms,
            commands::backups::delete_steam_backups,
            commands::disk::get_disk_usage,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
