# Velotype workflow-extension map

Velotype is a native Rust/GPUI Markdown editor with a clean separation between app wiring, editor state, block runtime, Markdown parsing/serialization, theming, i18n, and export. For John/4nix workflows, the most useful extension points are below.

## Existing no-code customization seams

- **Preferences/config:** `src/config/preferences.rs` via `src/config/mod.rs` stores TOML preferences under the OS config dir from `directories::ProjectDirs` (`com/manyougz/Velotype`). It already controls default theme/language, recent files, table-header visibility, startup behavior, image paste behavior, and keybindings.
- **Themes:** `assets/custom-theme.example.jsonc`, `src/theme/*`. Themes are JSONC imports normalized to JSON and can override colors, typography, spacing, menus, dialogs, table controls, image placeholders, code highlighting, and layout tokens.
- **Language packs:** `assets/custom-language.example.jsonc`, `src/i18n/*`. Same partial override/fallback approach as themes.
- **Keybindings:** `src/components/actions.rs` defines GPUI actions, default keys, categories, config schema, and normalization. This is the lowest-friction place to align with the workstation keyboard/Helix/Zed conventions.

## Code extension seams

1. **CLI and launch behavior**
   - File: `src/main.rs`
   - Current behavior: `velotype [OPTIONS] [FILES...]`, opens one window per file, with `--version`, `--help`, and macOS-only `--detach`.
   - Workflow ideas: add `--config-dir`, `--profile`, `--new-from-template`, `--stdin`, `--export html|pdf`, or `--workspace <dir>` for terminal-driven authoring.

2. **App menus and recent-file integration**
   - File: `src/app_menu.rs`
   - Current behavior: native/fallback menus, open/save/export/preferences/theme/language/recent files.
   - Workflow ideas: add menu commands for opening notes roots, daily notes, capture inbox, Forgejo/project docs, or invoking external tools.

3. **Editor controller and workspace mode**
   - Files: `src/editor/mod.rs`, `src/editor/workspace.rs`, related `editor/*` modules.
   - Current behavior: owns view mode, file path, dirty state, save/close flow, undo, selection, source mapping, export, drag/drop, and workspace outline state.
   - Workflow ideas: make workspace roots configurable, add project-local note index, backlinks, file tree filters, outline persistence, or jump-to-heading/project commands.

4. **Block runtime and interaction model**
   - Files: `src/components/block/runtime/*`, `src/components/block/interactions.rs`, `src/components/block/render.rs`.
   - Current behavior: native block tree for headings, paragraphs, lists, task lists, quotes/callouts, code, math, tables, images, HTML fallbacks, inline projection, and source editing.
   - Workflow ideas: custom callout/admonition types, frontmatter block, task metadata, keyboard-first block movement, journal/date blocks, transclusion/embed blocks, or richer table navigation.

5. **Markdown parser/serializer**
   - Files: `src/components/markdown/*`, `src/editor/document.rs`, `src/editor/persistence.rs`.
   - Current behavior: parses supported Markdown into blocks and serializes canonical Markdown, preserving unstable syntax as raw/source fallback.
   - Workflow ideas: enforce house Markdown style, preserve/round-trip YAML frontmatter, add wikilinks, hashtags, task due dates, citation keys, or project-specific fenced blocks.

6. **Export pipeline**
   - Files: `src/export/mod.rs`, `src/export/html.rs`, `src/export/pdf.rs`.
   - Current behavior: HTML and PDF export from current Markdown plus active theme CSS.
   - Workflow ideas: add Typst/Quarto/Pandoc export, site-ready HTML fragments, PDF presets, print styles, or CI-friendly headless export commands.

7. **Network/image handling**
   - Files: `src/net/*`, `src/components/block/runtime/image.rs`, `src/components/markdown/image.rs`.
   - Current behavior: remote/local image loading, paste handling, standalone image markdown.
   - Workflow ideas: built-in image hosting is already on the upstream roadmap. For 4nix, implement paste-to-assets-dir, content-addressed images, or Forgejo/Cloudflare upload backends.

## Recommended first workflow patches

1. **Declarative config path/profile support**: add `VELOTYPE_CONFIG_DIR` or `--config-dir` so Nix/Home Manager can install profile-specific theme/keybinding/preferences without mutating the upstream default config location.
2. **Helix/Zed-aligned keybinding profile**: encode your editor muscle memory in `src/components/actions.rs` defaults or a packaged config file.
3. **Markdown frontmatter + wikilink preservation**: useful for notes/docs repositories and low risk if implemented as structured blocks with raw fallback.
4. **Headless export CLI**: `velotype --export pdf input.md --output out.pdf` would make the package useful in scripts and CI, not just interactively.
5. **Paste images to repo assets**: when editing a Markdown file, copy pasted images into `./assets/` or sibling media dir and insert relative Markdown links.

## Packaging note

Velotype now lives as a local Git checkout at `/home/john/infrastructure/velotype` with its own flake. That flake owns the reusable package, app, overlay, and Home Manager module. 4nix consumes it as `git+file:///home/john/infrastructure/velotype`, follows 4nix's nixpkgs/home-manager pins, exposes `.#velotype` as a pass-through package/app, and enables `programs.velotype` from the Velotype HM module in the Markdown editor aspect.
