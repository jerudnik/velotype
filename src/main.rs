//! Velotype - a block-based Markdown editor built with GPUI.
//!
//! Reads file paths from command-line arguments and opens one GPUI window per
//! file. With no arguments, a single empty window is created.

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::borrow::Cow;
use std::path::PathBuf;
#[cfg(target_os = "macos")]
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};

#[cfg(target_os = "macos")]
use futures::{StreamExt, channel::mpsc};
use gpui::*;

mod app_identity;
mod app_menu;
mod components;
mod config;
mod editor;
mod export;
#[cfg(any(target_os = "macos", test))]
mod file_url;
mod i18n;
mod net;
mod theme;
mod window_chrome;

use app_menu::{init as init_app_menu, open_editor_window};
use components::init_with_keybindings as init_editor;
#[cfg(target_os = "macos")]
use file_url::parse_file_url;
use i18n::I18nManager;
use theme::ThemeManager;

#[derive(Clone, Debug)]
struct ExportRequest {
    format: export::ExportFormat,
    input: PathBuf,
    output: PathBuf,
    theme: Option<String>,
}

struct VelotypeAssets;

fn open_startup_window(cx: &mut App, startup_open: config::StartupOpenPreference) {
    if startup_open == config::StartupOpenPreference::LastOpenedFile
        && let Some(path) = config::first_existing_recent_markdown_file()
    {
        match std::fs::read_to_string(&path) {
            Ok(markdown) => {
                open_editor_window(cx, markdown, Some(path));
                return;
            }
            Err(err) => {
                eprintln!(
                    "failed to read last opened file '{}': {err}",
                    path.display()
                );
            }
        }
    }

    open_editor_window(cx, String::new(), None);
}

impl AssetSource for VelotypeAssets {
    fn load(&self, path: &str) -> gpui::Result<Option<Cow<'static, [u8]>>> {
        match path {
            "icon/workspace/folder.svg" => Ok(Some(Cow::Borrowed(include_bytes!(
                "../assets/icon/workspace/folder.svg"
            )))),
            "icon/workspace/markdown.svg" => Ok(Some(Cow::Borrowed(include_bytes!(
                "../assets/icon/workspace/markdown.svg"
            )))),
            "icon/titlebar/chrome-close.svg" => Ok(Some(Cow::Borrowed(include_bytes!(
                "../assets/icon/titlebar/chrome-close.svg"
            )))),
            "icon/titlebar/chrome-minimize.svg" => Ok(Some(Cow::Borrowed(include_bytes!(
                "../assets/icon/titlebar/chrome-minimize.svg"
            )))),
            "icon/titlebar/chrome-maximize.svg" => Ok(Some(Cow::Borrowed(include_bytes!(
                "../assets/icon/titlebar/chrome-maximize.svg"
            )))),
            "icon/titlebar/chrome-restore.svg" => Ok(Some(Cow::Borrowed(include_bytes!(
                "../assets/icon/titlebar/chrome-restore.svg"
            )))),
            _ => Ok(None),
        }
    }

    fn list(&self, _path: &str) -> gpui::Result<Vec<SharedString>> {
        Ok(Vec::new())
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();

    // Parse command-line arguments
    let mut config_dir: Option<PathBuf> = None;
    let mut detach = false;
    let mut export_format: Option<export::ExportFormat> = None;
    let mut export_output: Option<PathBuf> = None;
    let mut export_theme: Option<String> = None;
    let mut input_paths = Vec::new();
    let mut profile: Option<String> = None;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--version" | "-v" => {
                println!("velotype {}", env!("CARGO_PKG_VERSION"));
                return;
            }
            "--help" | "-h" => {
                println!(
                    "velotype {} - A block-based Markdown editor",
                    env!("CARGO_PKG_VERSION")
                );
                println!();
                println!("USAGE:");
                println!("    velotype [OPTIONS] [FILES...]");
                println!();
                println!("OPTIONS:");
                println!("    -v, --version    Print version information");
                println!("    -h, --help       Print this help message");
                println!("    -d, --detach     Launch in background (non-blocking)");
                println!("        --config-dir DIR");
                println!(
                    "                    Use DIR instead of the platform Velotype config directory"
                );
                println!("        --profile NAME");
                println!(
                    "                    Use a named config profile under the config directory"
                );
                println!("        --export FORMAT");
                println!(
                    "                    Export one input file headlessly; FORMAT is html or pdf"
                );
                println!("        --output PATH");
                println!("                    Output path for --export");
                println!("        --theme THEME");
                println!("                    Theme id or theme JSON/JSONC path used for --export");
                println!();
                println!("FILES:");
                println!("    One or more markdown files to open. If no files are specified,");
                println!("    opens an empty document.");
                return;
            }
            "--detach" | "-d" => {
                detach = true;
            }
            "--config-dir" => {
                i += 1;
                let Some(path) = args.get(i) else {
                    eprintln!("--config-dir requires a directory path");
                    std::process::exit(1);
                };
                config_dir = Some(PathBuf::from(path));
            }
            "--profile" => {
                i += 1;
                let Some(name) = args.get(i) else {
                    eprintln!("--profile requires a profile name");
                    std::process::exit(1);
                };
                profile = Some(name.clone());
            }
            "--export" => {
                i += 1;
                let Some(format) = args.get(i) else {
                    eprintln!("--export requires a format: html or pdf");
                    std::process::exit(1);
                };
                let Some(format) = export::ExportFormat::from_str(format) else {
                    eprintln!("unsupported export format '{format}': expected html or pdf");
                    std::process::exit(1);
                };
                export_format = Some(format);
            }
            "--output" | "-o" => {
                i += 1;
                let Some(path) = args.get(i) else {
                    eprintln!("--output requires a path");
                    std::process::exit(1);
                };
                export_output = Some(PathBuf::from(path));
            }
            "--theme" => {
                i += 1;
                let Some(theme) = args.get(i) else {
                    eprintln!("--theme requires a theme id or theme file path");
                    std::process::exit(1);
                };
                export_theme = Some(theme.clone());
            }
            option if option.starts_with('-') => {
                eprintln!("Unknown option: {}", option);
                std::process::exit(1);
            }
            path => {
                input_paths.push(PathBuf::from(path));
            }
        }
        i += 1;
    }

    let export_request = if let Some(format) = export_format {
        if detach {
            eprintln!("--detach cannot be used with --export");
            std::process::exit(1);
        }
        if input_paths.len() != 1 {
            eprintln!("--export requires exactly one input markdown file");
            std::process::exit(1);
        }
        let Some(output) = export_output else {
            eprintln!("--export requires --output PATH");
            std::process::exit(1);
        };
        Some(ExportRequest {
            format,
            input: input_paths.remove(0),
            output,
            theme: export_theme,
        })
    } else {
        if export_output.is_some() {
            eprintln!("--output requires --export");
            std::process::exit(1);
        }
        if export_theme.is_some() {
            eprintln!("--theme requires --export");
            std::process::exit(1);
        }
        None
    };

    if let Some(config_dir) = config_dir {
        match config::RuntimeConfigPaths::new(config_dir, profile) {
            Ok(paths) => config::set_runtime_config_paths(paths),
            Err(err) => {
                eprintln!("{err}");
                std::process::exit(1);
            }
        }
    } else if let Some(profile) = profile {
        let Some(project_dirs) = directories::ProjectDirs::from("com", "manyougz", "Velotype")
        else {
            eprintln!("failed to resolve the Velotype config directory");
            std::process::exit(1);
        };
        match config::RuntimeConfigPaths::new(
            project_dirs.config_dir().to_path_buf(),
            Some(profile),
        ) {
            Ok(paths) => config::set_runtime_config_paths(paths),
            Err(err) => {
                eprintln!("{err}");
                std::process::exit(1);
            }
        }
    }

    if let Some(request) = export_request {
        let preferences = config::load_or_create_app_preferences().unwrap_or_else(|err| {
            eprintln!("failed to initialize app preferences: {err}");
            Default::default()
        });
        let mut theme_manager = ThemeManager::default();
        if let Some(theme) = request.theme.as_deref() {
            let theme_path = PathBuf::from(theme);
            if theme_path.exists() {
                if let Err(err) = theme_manager.load_file(&theme_path) {
                    eprintln!(
                        "failed to load export theme '{}': {err:#}",
                        theme_path.display()
                    );
                    std::process::exit(1);
                }
            } else if !theme_manager.set_theme_by_id(theme) {
                eprintln!(
                    "unknown export theme '{theme}': use a built-in theme id or a theme JSON/JSONC file path"
                );
                std::process::exit(1);
            }
        } else {
            let _ = theme_manager.set_theme_by_id(&preferences.default_theme_id);
        }
        if let Err(err) = export::export_document_file(
            &request.input,
            &request.output,
            request.format,
            theme_manager.current(),
        ) {
            eprintln!("export failed: {err:#}");
            std::process::exit(1);
        }
        return;
    }

    #[cfg(not(target_os = "macos"))]
    let _ = detach;

    // On macOS, detach from terminal if requested
    // TODO: Other platforms may also need to be adapted
    #[cfg(target_os = "macos")]
    if detach {
        use std::process::Command;

        // Re-launch the application in the background without the --detach flag
        let exe_path = std::env::current_exe().expect("Failed to get executable path");
        let non_detach_args: Vec<String> = args
            .iter()
            .filter(|arg| *arg != "--detach" && *arg != "-d")
            .cloned()
            .collect();

        Command::new(exe_path)
            .args(&non_detach_args[1..])
            .spawn()
            .expect("Failed to detach process");

        return;
    }

    #[cfg(target_os = "macos")]
    let (open_file_tx, mut open_file_rx) = mpsc::unbounded::<PathBuf>();
    #[cfg(target_os = "macos")]
    let open_file_requested = Arc::new(AtomicBool::new(false));

    let app = Application::new().with_assets(VelotypeAssets);

    #[cfg(target_os = "macos")]
    {
        let open_file_requested_for_callback = open_file_requested.clone();
        app.on_open_urls(move |urls| {
            for url in urls {
                let Some(path) = parse_file_url(&url) else {
                    continue;
                };
                open_file_requested_for_callback.store(true, Ordering::SeqCst);
                let _ = open_file_tx.unbounded_send(path);
            }
        });
    }

    app.run(move |cx: &mut App| {
        let preferences = config::load_or_create_app_preferences().unwrap_or_else(|err| {
            eprintln!("failed to initialize app preferences: {err}");
            Default::default()
        });
        I18nManager::init_with_language_id(cx, &preferences.default_language_id);
        ThemeManager::init_with_theme_id(cx, &preferences.default_theme_id);
        config::EditorSettings::init(cx, preferences.show_table_headers);
        net::install_http_client(cx);
        let effective_keybindings = preferences.effective_keybindings();
        init_editor(cx, &effective_keybindings);
        init_app_menu(cx);

        #[cfg(target_os = "macos")]
        cx.spawn(async move |cx| {
            while let Some(path) = open_file_rx.next().await {
                let _ = cx.update(move |cx| {
                    if let Err(err) = app_menu::open_file_in_new_window(cx, &path) {
                        eprintln!("failed to open '{}': {err}", path.display());
                    }
                });
            }
        })
        .detach();

        if input_paths.is_empty() {
            #[cfg(target_os = "macos")]
            {
                let startup_open = preferences.startup_open;
                let open_file_requested = open_file_requested.clone();
                cx.spawn(async move |cx| {
                    cx.background_executor()
                        .timer(std::time::Duration::from_millis(150))
                        .await;
                    if !open_file_requested.load(Ordering::SeqCst) {
                        let _ = cx.update(move |cx| open_startup_window(cx, startup_open));
                    }
                })
                .detach();
            }

            #[cfg(not(target_os = "macos"))]
            open_startup_window(cx, preferences.startup_open);

            return;
        }

        for path in &input_paths {
            let absolute_path = if path.is_absolute() {
                path.clone()
            } else {
                match std::env::current_dir() {
                    Ok(cwd) => cwd.join(path),
                    Err(_) => path.clone(),
                }
            };

            let markdown = match std::fs::read_to_string(&absolute_path) {
                Ok(content) => {
                    if let Err(err) = config::record_recent_file(&absolute_path) {
                        eprintln!("failed to update recent file history: {err}");
                    }
                    content
                }
                Err(err) => {
                    eprintln!(
                        "failed to read '{}': {err}. opened as empty document.",
                        absolute_path.display()
                    );
                    String::new()
                }
            };
            open_editor_window(cx, markdown, Some(absolute_path));
        }
        app_menu::install_menus(cx);
        cx.refresh_windows();
    });
}
