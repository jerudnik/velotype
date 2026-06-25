//! Document export helpers for HTML and PDF output.
//!
//! Export starts from the same Markdown text used by document saving. The
//! module owns format-specific rendering so editor code only chooses paths and
//! supplies the current theme.

use std::path::Path;

use anyhow::Context as _;

use crate::theme::Theme;

mod html;
mod pdf;

/// Export target selected from the app menu.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum ExportFormat {
    /// Full HTML document with embedded theme CSS.
    Html,
    /// PDF bytes rendered from the themed HTML document.
    Pdf,
}

impl ExportFormat {
    /// File extension used for save-dialog defaults.
    pub(crate) fn extension(self) -> &'static str {
        match self {
            Self::Html => "html",
            Self::Pdf => "pdf",
        }
    }

    pub(crate) fn from_str(value: &str) -> Option<Self> {
        match value {
            "html" => Some(Self::Html),
            "pdf" => Some(Self::Pdf),
            _ => None,
        }
    }
}

pub(crate) use html::render_html_with_base_dir;

pub(crate) fn export_document_file(
    input: &Path,
    output: &Path,
    format: ExportFormat,
    theme: &Theme,
) -> anyhow::Result<()> {
    let markdown = std::fs::read_to_string(input)
        .with_context(|| format!("failed to read '{}'", input.display()))?;
    let title = input
        .file_stem()
        .and_then(|stem| stem.to_str())
        .filter(|stem| !stem.is_empty())
        .unwrap_or("Untitled");
    let base_path = input.parent();
    let bytes = match format {
        ExportFormat::Html => {
            render_html_with_base_dir(&markdown, theme, title, base_path).into_bytes()
        }
        ExportFormat::Pdf => render_pdf(&markdown, theme, title, base_path)?,
    };
    std::fs::write(output, bytes).with_context(|| format!("failed to write '{}'", output.display()))
}

/// Renders themed PDF bytes for the current document Markdown.
pub(crate) fn render_pdf(
    markdown: &str,
    theme: &Theme,
    title: &str,
    base_path: Option<&Path>,
) -> anyhow::Result<Vec<u8>> {
    pdf::render_pdf(markdown, theme, title, base_path)
}
