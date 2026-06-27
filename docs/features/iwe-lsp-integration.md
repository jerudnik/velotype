# IWE LSP Integration for Velotype

## Summary

Add optional, fail-soft IWE language server ([`iwes`](https://github.com/iwe-org/iwe)) support so Velotype—when editing inside a workspace/repo of interlinked Markdown files—can leverage IWE's knowledge-graph intelligence for wikilink completion, backlinks, hover previews, go-to-definition, rename-refactoring, and document structure navigation, all through the LSP protocol.

This documents a concrete feature design rather than an abstract idea. It targets the existing config → Nix → Home Manager → editor surfaces already in this fork.

## Why IWE specifically (vs markdown-oxide / Marksman)

IWE is already packaged in nixpkgs (`pkgs.iwe` builds `iwe`, `iwes`, and `iwec` from a single Rust workspace — nixpkgs-unstable / 26.05 carry v0.1.3). Its LSP surface covers the exact PKM features Velotype's roadmap calls for: wikilink completion, backlinks, rename with cross-file reference updates, document/workspace symbols, code actions (extract/inline/transform), and MCP-based AI agent integration. This makes it a single-binary dependency that maps cleanly onto Nix packaging—no extra servers, no plugin ecosystem to herd.

## Configuration design

### `[lsp.iwes]` section in `config.toml`

```toml
[lsp.iwes]
enable = false
command = "iwes"
args = []
root_marker = ".iwe"
debounce_ms = 500
features = [
  "completion",
  "hover",
  "definition",
  "references",
  "document_symbols",
  "workspace_symbols",
  "inlay_hints",
  "formatting",
  "code_actions",
  "rename",
]
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enable` | bool | `false` | Start `iwes` when a workspace root is detected |
| `command` | string | `"iwes"` | Path/name of the LSP server binary (allows `lib.getExe pkgs.iwe` override) |
| `args` | `[string]` | `[]` | Extra CLI args forwarded to `iwes` |
| `root_marker` | string | `".iwe"` | File/dir name that marks the workspace root |
| `debounce_ms` | u64 | `500` | Debounce window for didChange notifications |
| `features` | `[string]` | all enabled | Subset of LSP features to activate (omit to disable noisy features) |

Why opt-in (`enable = false` by default): Velotype is a single-file editor first. The iwes binary may not exist on the user's system. Fail-soft means the app still starts and edits normally; a status bar indicator shows whether the LSP is connected.

### Rust-side representation

```rust
// in src/config/preferences.rs

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct LspIwesPreferences {
    pub(crate) enable: bool,
    pub(crate) command: String,
    pub(crate) args: Vec<String>,
    pub(crate) root_marker: String,
    pub(crate) debounce_ms: u64,
    pub(crate) features: Vec<String>,
}

impl Default for LspIwesPreferences {
    fn default() -> Self {
        Self {
            enable: false,
            command: "iwes".into(),
            args: Vec::new(),
            root_marker: ".iwe".into(),
            debounce_ms: 500,
            features: vec![
                "completion".into(), "hover".into(), "definition".into(),
                "references".into(), "document_symbols".into(),
                "workspace_symbols".into(), "inlay_hints".into(),
                "formatting".into(), "code_actions".into(), "rename".into(),
            ],
        }
    }
}
```

This slots into the existing `AppPreferences` struct and its TOML serialize/deserialize path—same pattern as `WhichKeyPreferences` and `MarkdownExtensionPreferences`.

## Implementation plan (phased)

### Phase 1 — Config + Nix surface (no editor wiring)

**Files touched:**

- `src/config/preferences.rs` — add `LspIwesPreferences`, `LspPreferencesFile`, TOML read/write, and `Default`
- `nix/modules/home-manager.nix` — add `programs.velotype.lsp.iwes.*` options mirroring the config schema
- `nix/package.nix` — optionally wrap `iwes` onto PATH via `makeWrapper` when `pkgs.iwe` is provided as a parameter
- `flake.nix` — expose `iwe` as an optional package input so downstream flakes can pass it

**Nix design:**

```nix
# nix/package.nix — new optional parameter
, iwePackage ? null  # pkgs.iwe or null

# In postInstall, if provided:
${lib.optionalString (iwePackage != null) ''
  wrapProgram "$out/bin/velotype" \
    --prefix PATH : ${lib.makeBinPath [iwePackage]}
''}
```

```nix
# flake.nix — optional input (or resolved from nixpkgs)
perSystem = { ... }: {
  packages = {
    default = velotype;
    velotype = pkgs.callPackage ./nix/package.nix {
      inherit craneLib version;
      iwePackage = pkgs.iwe;  # from nixpkgs (fails gracefully if missing)
    };
  };
};
```

**Home Manager options:**

```nix
lsp.iwes.enable = lib.mkEnableOption "IWE LSP integration for Markdown workspace intelligence";
lsp.iwes.command = lib.mkOption {
  type = lib.types.str;
  default = "${lib.getExe pkgs.iwe}";
  description = "Path to the iwes LSP server binary.";
};
lsp.iwes.rootMarker = lib.mkOption {
  type = lib.types.str;
  default = ".iwe";
};
lsp.iwes.debounceMs = lib.mkOption {
  type = lib.types.ints.unsigned;
  default = 500;
};
lsp.iwes.features = lib.mkOption {
  type = lib.types.listOf (lib.types.enum [
    "completion" "hover" "definition" "references"
    "document_symbols" "workspace_symbols" "inlay_hints"
    "formatting" "code_actions" "rename"
  ]);
  default = [ /* all */ ];
};
```

When the HM module writes `config.toml`, it includes the `[lsp.iwes]` section with the user's choices.

### Phase 2 — LSP client subprocess + document sync (read-only)

**New file: `src/lsp/mod.rs`**

- Spawn `iwes` as a child process with stdio pipes
- Implement JSON-RPC framing (Content-Length header + body) over stdin/stdout
- Send `initialize`, `initialized`, `textDocument/didOpen`, `textDocument/didChange` (debounced)
- Receive and parse responses/notifications (`textDocument/publishDiagnostics`, `window/showMessage`)
- Attach diagnostics to blocks via source-mapping positions

**Dependency:** `lsp-types` crate (wire types) + `serde_json` (already a dep)

**Key constraint:** Velotype's block tree means text positions must be mapped between serialized Markdown (what LSP sees) and the block model (what the editor manipulates). For read-only Phase 2 features (diagnostics, hover, symbols), the source text is the canonical position space. The existing `SourceTargetMapping` infrastructure in `src/editor/source_mapping.rs` handles block ↔ source offset translation.

**Concurrency model:** Run the LSP JSON-RPC loop on a background `tokio` task (already a dependency). Communicate with the editor via `gpui::Model` messages.

### Phase 3 — Completion, hover, go-to-definition

Build on the LSP client from Phase 2:

- **Completion:** When the user types `[[` in a text block, trigger `textDocument/completion`. Show IWE's wikilink suggestions in a GPUI popover anchored to the cursor. Accepting a suggestion inserts the wikilink text.

- **Hover:** When the cursor rests on a wikilink `[[target]]` or Markdown link `[text](target.md)`, send `textDocument/hover`. Display the hover content (target title, backlink count, preview) as a GPUI tooltip.

- **Go-to-definition:** When the user activates "go to definition" on a link, send `textDocument/definition`. IWE returns the target file URI + range. Velotype opens the target file in a new editor tab (reusing the existing workspace infrastructure at `src/editor/workspace.rs`).

- **Find references / backlinks:** Send `textDocument/references` from the current file position. Display results in the workspace sidebar as a list of `(source_file, line, context_snippet)` entries.

### Phase 4 — Code actions, rename, formatting (mutation)

Only after position mapping is verified robust:

- **Rename:** `textDocument/rename` — user renames a note file; IWE updates all cross-file wikilinks automatically. Velotype's `WorkspaceState` already tracks open documents.

- **Code actions:** `textDocument/codeAction` — IWE provides extract-section-to-new-note, inline-note, transform-list-to-headers, etc. Velotype shows these in a command palette or context menu.

- **Formatting:** `textDocument/formatting` — IWE normalizes document structure. Apply the text edits, re-parse the block tree from the formatted Markdown.

## Nix-friendly design principles

1. **IWE is an optional runtime dependency, not a build dependency.** The Rust crate compiles without `iwes` present. It searches `PATH` at runtime.

2. **The Nix package wrapper can bake in the path.** When `iwePackage` is provided, `makeWrapper --prefix PATH : ${lib.makeBinPath [iwePackage]}` puts `iwes` on the wrapped binary's PATH. Downstream users who don't enable the feature pay zero cost.

3. **Home Manager module stays flat and declarative.** Users configure `programs.velotype.lsp.iwes.enable = true` and the HM module writes the corresponding `config.toml` section. No imperative scripting.

4. **Fail-soft everywhere.** If `iwes` isn't on PATH, isn't executable, crashes, or returns errors—Velotype continues editing normally. A status indicator (icon + tooltip) shows LSP state.

5. **No flake input lock-in.** The flake resolves `iwe` from nixpkgs (already an input via flake-parts), not a separate flake input. This avoids pinning conflicts.

## Configuration surface comparison

| Layer | What's configured |
|-------|-------------------|
| `config.toml` (`[lsp.iwes]`) | enable, command, args, root_marker, debounce_ms, features |
| Home Manager (`programs.velotype.lsp.iwes`) | Mirrors the above, Nix-native types |
| Flake (`packages.${system}.velotype`) | Optional `iwePackage` parameter for PATH wrapping |
| Rust (`AppPreferences`) | Deserialized at startup, available as `Global` or editor field |

This follows the exact same layered-config pattern already used by `which_key`, `markdown_extensions`, and `images` in this codebase.

## Acceptance criteria

1. A `velotype` binary built with Nix where `iwePackage = pkgs.iwe` has `iwes` on its wrapped PATH.
2. `programs.velotype.lsp.iwes.enable = true` in Home Manager writes `[lsp.iwes] enable = true` to `config.toml`.
3. When `enable = true` and `iwes` is on PATH, Velotype spawns the LSP on workspace open and logs connection status (no crash on missing binary).
4. Diagnostics from IWE appear as inline markers on affected blocks.
5. Typing `[[` triggers wikilink completion suggestions from the workspace.
6. Hovering a wikilink shows target metadata in a tooltip.
7. "Go to definition" on a valid wikilink opens the target file.
