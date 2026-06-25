# Velotype extension-boundary design

This document defines the customization boundary for John's Velotype fork. The goal is not a dynamic plugin ABI. Velotype's GPUI state, parser, block runtime, and export code are tightly coupled Rust internals, so a true plugin system would add instability before the app has stable extension APIs. Instead, we will introduce a small, typed runtime configuration boundary that keeps workflow changes declarative, testable, and gradually upstreamable.

## Goals

- Keep workflow behavior configurable from `config.toml`, CLI flags, environment variables, and Home Manager.
- Avoid hard-coded John-only behavior in editor internals.
- Keep each feature branch small and stacked:
  1. config directory/profile/runtime boundary
  2. config-driven keybindings and which-key menu
  3. repo-local asset paste workflow
  4. Markdown extension round-tripping: frontmatter and wikilinks first
  5. headless export CLI
- Preserve Velotype's existing fallback behavior when no custom config is present.
- Add tests at the boundary, not just through UI code.

## Non-goals

- No dynamic shared-library/plugin loading.
- No scripting VM.
- No breaking migration of existing `config.toml` keys.
- No workspace/backlink/index feature in this stack. That can build on the Markdown-extension work later.

## Current seams

| Area | Current files | Current behavior | Boundary change |
| --- | --- | --- | --- |
| App launch | `src/main.rs` | Hand-rolled args: `--help`, `--version`, `--detach`, files | Introduce parsed `LaunchOptions` and early command dispatch |
| Config dirs | `src/config/mod.rs` | `ProjectDirs::from("com", "manyougz", "Velotype")` only | Introduce `RuntimeConfigPaths` with env/CLI override |
| Preferences | `src/config/preferences.rs` | Reads/writes `config.toml`; stores startup/theme/language/table/image/keybindings | Split persistent preferences from process runtime options |
| Keybindings | `src/components/actions.rs` | Static definitions plus config override map | Add profile-aware shortcut config and command metadata for which-key |
| Which-key/discovery | none explicit | Preferences UI lists shortcuts, no transient command palette | Use action metadata to render a keyboard-discovery overlay |
| Image paste | `src/editor/events.rs`, `src/components/block/interactions.rs`, image runtime modules | Image paste behavior enum supports broad destinations | Add configurable asset directory/naming and repo-relative insertion |
| Markdown extensions | `src/components/markdown/*`, `src/editor/document.rs`, persistence | Supported Markdown -> blocks; unstable syntax remains source/raw | Add extension config and round-trip tests for frontmatter/wikilinks |
| Export | `src/export/*`, `src/editor/export.rs` | GUI export to HTML/PDF via current theme | Add CLI command path that reuses export renderers |

## Proposed runtime boundary

Add a new small module, likely `src/runtime_config.rs` or `src/config/runtime.rs`, that owns process-level options and resolved paths.

```rust
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct LaunchOptions {
    pub(crate) config_dir: Option<PathBuf>,
    pub(crate) profile: Option<String>,
    pub(crate) command: LaunchCommand,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum LaunchCommand {
    Gui { files: Vec<PathBuf>, detach: bool },
    Export(ExportCommand),
    Help,
    Version,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct RuntimeConfigPaths {
    pub(crate) root: PathBuf,
    pub(crate) profile: Option<String>,
}
```

Resolution order:

1. CLI `--config-dir PATH`
2. env `VELOTYPE_CONFIG_DIR`
3. default platform config directory from `directories::ProjectDirs`

Profile handling:

- `--profile NAME` or `VELOTYPE_PROFILE=NAME` maps config files under `<root>/profiles/<name>/`.
- No profile preserves current layout exactly: `<root>/config.toml`, `<root>/themes`, `<root>/languages`, `<root>/.history`.
- With profile: `<root>/profiles/<name>/config.toml`, `themes`, `languages`, `.history`.

This keeps the default app behavior stable while giving Nix/HM a clean declarative target.

## Persistent configuration shape

Keep existing top-level TOML sections and add narrow new sections:

```toml
[startup]
open = "new_file"

[language]
default_language_id = "en-US"

[theme]
default_theme_id = "velotype"

[editor]
show_table_headers = true
image_paste_behavior = "copy_to_assets_folder"

[keybindings]
save_document = ["ctrl-s"]

[keybinding_profiles.john]
save_document = ["ctrl-s"]
toggle_which_key = ["space", "?"]

[which_key]
enable = true
trigger = ["ctrl-space"]
timeout_ms = 1200

[images]
asset_dir = "assets"
naming = "slug-counter" # later: "content-hash"
relative_to = "document" # later: "workspace"

[markdown_extensions]
frontmatter = true
wikilinks = true

[export]
default_format = "html"
```

Important: existing `[keybindings]` remains valid. Profiles are additive and selected by `keybinding_profile = "john"` if we add that field, or by runtime profile if unset.

## Keybindings and which-key design

Current `ShortcutDefinition` already has most metadata required for a which-key menu:

- command enum
- stable id
- category
- default keys
- GPUI context

Add/extend metadata with:

- display label key or fallback label
- optional which-key group
- optional hidden flag for commands that should not appear

Minimal shape:

```rust
pub(crate) struct ShortcutDefinition {
    pub(crate) command: ShortcutCommand,
    pub(crate) id: &'static str,
    pub(crate) category: ShortcutCategory,
    pub(crate) default_keys: &'static [&'static str],
    pub(crate) context: Option<&'static str>,
    pub(crate) label: &'static str,
    pub(crate) which_key_group: ShortcutCategory,
}
```

Which-key UI should be a GPUI overlay/dialog owned at the editor/window layer, not inside individual blocks. It should show resolved keys, grouped by category, using `resolved_shortcut_keys(&preferences.keybindings)` as the source of truth.

Implemented first pass:

- `keybinding_profile = "name"` selects `[keybinding_profiles.name]`.
- The selected profile is merged over base `[keybindings]`, so profiles can override only the shortcuts that differ.
- `[which_key] enable = true` and `trigger = ["ctrl-space"]` are persisted and exposed through Home Manager.
- `toggle_which_key` is a normal shortcut id, so users can bind the overlay from base keybindings or a selected profile.
- The editor renders a transient, dismissible GPUI overlay grouped by the existing shortcut categories.

Implementation path:

1. Add `ToggleWhichKey` action.
2. Add shortcut definition for it.
3. Store `which_key` prefs in `AppPreferences`.
4. Add editor state `show_which_key: bool`.
5. Render an overlay panel from command metadata.
6. Bind default trigger conservatively, likely no default or `ctrl-space` until John profile sets a preferred binding.

## Image paste boundary

Existing `ImagePasteBehavior` is a good start, but it mixes behavior choice with implicit destination/naming. Add `ImagePasteSettings`:

```rust
pub(crate) struct ImagePasteSettings {
    pub(crate) behavior: ImagePasteBehavior,
    pub(crate) asset_dir: PathBuf,
    pub(crate) naming: ImageNamingStrategy,
}
```

Initial strategies:

- `original-counter`: preserve stem, append `-2`, `-3` on conflicts.
- `slug-counter`: derive from document stem or alt text when available.

Later strategy:

- `content-hash`: hash bytes and deduplicate.

Relative links should be computed from the Markdown document's parent directory. If unsaved, fall back to current behavior or ask to save first.

Implemented first pass:

- `[images] asset_dir = "assets"` controls the destination for `copy_to_assets_folder`.
- `[images] naming = "original-counter" | "slug-counter"` controls copied file names before the existing collision counter is applied.
- Home Manager exposes the same values as `programs.velotype.images.asset_dir` and `programs.velotype.images.naming`.
- Existing `editor.image_paste_behavior` remains the behavior switch, preserving old defaults.

## Markdown extension boundary

Avoid making every Markdown feature a bespoke parser hack. Add a simple extension config consumed by parser/serializer code:

```rust
pub(crate) struct MarkdownExtensionConfig {
    pub(crate) frontmatter: bool,
    pub(crate) wikilinks: bool,
}
```

Frontmatter first:

- Detect only at byte start: `---\n...\n---\n`.
- Preserve exact source text unless edited through a later structured UI.
- Render as a collapsible/source-like metadata block initially.
- Serialize byte-for-byte when unchanged.

Wikilinks second:

- Parse `[[target]]` and `[[target|label]]` as inline link-like segments.
- Render as internal links but serialize back to wikilink syntax.
- Keep invalid/nested forms as plain text.

Tests should be round-trip-first:

- parse -> serialize equals input for frontmatter-only, wikilink-only, mixed docs.
- edit adjacent normal Markdown without losing extension syntax.

Implemented first pass:

- YAML frontmatter at the start of a document is collected as an exact raw Markdown block and round-trips unchanged.
- Existing inline parsing already preserves unsupported inline syntax, including `[[Page]]` and `[[Page|Alias]]`, so focused wikilink round-trip coverage was added.
- `[markdown_extensions] frontmatter = true` and `wikilinks = true` are persisted and exposed through Home Manager as `programs.velotype.markdownExtensions.*`.

## Headless export CLI boundary

Extend `LaunchCommand`:

```rust
pub(crate) struct ExportCommand {
    pub(crate) input: PathBuf,
    pub(crate) output: PathBuf,
    pub(crate) format: ExportFormat,
    pub(crate) config_dir: Option<PathBuf>,
    pub(crate) profile: Option<String>,
    pub(crate) theme_id: Option<String>,
}
```

CLI examples:

```bash
velotype --export html README.md --output README.html
velotype --export pdf README.md --output README.pdf --theme velotype-light
```

HTML export can be purely headless. PDF may still need Chromium through `chromiumoxide`; the command should provide an actionable error if Chromium cannot launch in the current environment.

Implemented first pass:

- `velotype --export html INPUT.md --output OUTPUT.html` exports without opening a GPUI window.
- `velotype --export pdf INPUT.md --output OUTPUT.pdf` routes through the existing PDF renderer and returns a normal CLI error if Chromium/PDF rendering fails.
- `--theme THEME` selects a built-in theme id or a theme JSON/JSONC file path for headless export; when omitted, export uses the configured profile/default theme.
- The command respects `--config-dir` and `--profile` before loading preferences/theme.
- GUI behavior is unchanged when `--export` is absent.

## Home Manager integration

The HM module should target the same boundary:

- `programs.velotype.configDir` or `profile`
- `programs.velotype.keybindings`
- `programs.velotype.keybindingProfiles`
- `programs.velotype.whichKey`
- `programs.velotype.images`
- `programs.velotype.markdownExtensions`
- `programs.velotype.export`

For immutable/declarative configs, prefer writing a profile-specific config and launching Velotype with either wrapper env or `--profile john`. If the app must mutate preferences, the user profile can be mutable while a Nix-provided profile remains a template.

## Branch stack

1. `stack/01-extension-boundary`
   - This design doc.
   - Add no behavior unless needed for compile-neutral scaffolding.

2. `stack/02-config-dir-profile`
   - `LaunchOptions`, config dir/profile resolution, tests.
   - HM module update.

3. `stack/03-keybindings-whichkey`
   - Shortcut metadata cleanup.
   - Config-driven profiles.
   - Which-key overlay.

4. `stack/04-repo-assets-image-paste`
   - Image paste settings and repo-relative asset copy.

5. `stack/05-markdown-extensions-roundtrip`
   - Frontmatter, wikilinks, tests.

6. `stack/06-headless-export-cli`
   - Export command parser/path.
   - HTML/PDF validation.

## Validation checklist

Per branch:

- `cargo fmt`
- targeted `cargo test` for changed modules
- `nix build .#velotype --no-link`
- `nix run .# -- --version`
- HM check if Nix module changed: `nix build .#checks.x86_64-linux.hm-module --no-link`

For branches that touch parser/serializer, add explicit round-trip fixtures.
