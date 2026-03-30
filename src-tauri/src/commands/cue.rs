use std::path::PathBuf;
use tauri::AppHandle;
use tauri_plugin_dialog::DialogExt;

#[derive(serde::Serialize)]
pub struct CueFileResult {
    pub file: String,
    pub status: String,
    pub msg: String,
}

#[derive(serde::Serialize)]
pub struct CueResult {
    pub canceled: bool,
    pub results: Vec<CueFileResult>,
}

#[tauri::command]
pub async fn generate_cue(app: AppHandle) -> Result<CueResult, String> {
    let file_paths = app
        .dialog()
        .file()
        .add_filter("BIN files", &["bin"])
        .blocking_pick_files();

    let paths = match file_paths {
        Some(paths) => paths,
        None => {
            return Ok(CueResult {
                canceled: true,
                results: vec![],
            })
        }
    };

    let mut results = Vec::new();

    for file_path in paths {
        let bin_path: PathBuf = file_path.into_path().map_err(|e| e.to_string())?;
        let bin_filename = bin_path
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string();
        let cue_path = bin_path.with_extension("cue");

        if cue_path.exists() {
            results.push(CueFileResult {
                file: bin_filename,
                status: "skipped".into(),
                msg: ".cue already exists".into(),
            });
            continue;
        }

        let cue_content = format!(
            "FILE \"{}\" BINARY\n  TRACK 01 MODE2/2352\n    INDEX 01 00:00:00\n",
            bin_filename
        );

        match std::fs::write(&cue_path, &cue_content) {
            Ok(_) => results.push(CueFileResult {
                file: bin_filename,
                status: "ok".into(),
                msg: format!(
                    "Created {}",
                    cue_path
                        .file_name()
                        .unwrap_or_default()
                        .to_string_lossy()
                ),
            }),
            Err(e) => results.push(CueFileResult {
                file: bin_filename,
                status: "error".into(),
                msg: e.to_string(),
            }),
        }
    }

    Ok(CueResult {
        canceled: false,
        results,
    })
}
