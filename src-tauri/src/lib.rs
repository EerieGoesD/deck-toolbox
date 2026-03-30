mod commands;

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            commands::scripts::cache_sudo,
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
            commands::backups::delete_steam_backups,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
