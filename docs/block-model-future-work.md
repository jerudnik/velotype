# Velotype block-model future work

This note captures future extension ideas enabled by Velotype's block-based Markdown model. These are not immediate commitments. They are intention-capture records meant to preserve why each idea is valuable, where it would fit, and what implementation pitfalls to expect.

## 1. Structural block editing

### Intention capture

- **What it can do:** Provide commands that operate on whole semantic blocks or block ranges: move block up/down, duplicate block, delete block, promote/demote heading, fold a heading subtree, split/merge paragraph blocks, and normalize list nesting.
- **What it is useful for:** Fast document reshaping without thinking in raw Markdown line ranges. Especially useful for long notes, outlines, design docs, meeting notes, and technical writeups where sections move around during editing.
- **When to use it:** When the user is thinking in document structure: “move this section above that one”, “turn these paragraphs into a callout”, “promote this subsection”, or “duplicate this checklist”.
- **What it would not be useful for:** Character-level editing, precise source formatting edits, or arbitrary Markdown syntax Velotype does not understand. Helix/Zed remain better for raw text surgery.
- **Expected behavior / vignette:** John opens a project planning note, focuses a heading named “Risks”, presses a command, and the entire heading subtree moves above “Milestones” while all nested lists, code fences, and raw Markdown blocks remain intact. The saved `.md` file is normal Markdown with no editor-only storage.
- **Surface it touches:** Editor commands/actions, block selection, document tree mutations, keyboard bindings/which-key metadata, serialization tests.

### Implementation details

- **Surfaces touched:** `src/editor/document.rs` for tree operations, `src/editor/selection.rs` for block/range selection, `src/editor/events.rs` or action handlers for command dispatch, `src/components/actions.rs` for command metadata, and round-trip tests under `src/editor/document.rs` or `src/editor/tests.rs`.
- **Starting patterns/examples:** Existing block parsing and serialization in `Editor::from_markdown` and `DocumentTree::markdown_text`; current action metadata in `src/components/actions.rs`; the which-key overlay added for shortcut discovery can expose new structural commands.
- **Adaptation considerations:** Prefer operations on `BlockRecord`/document tree identities rather than string manipulation. For heading subtree moves, compute a structural range from heading depth to the next heading of equal or higher depth. For list normalization, be careful about nested list continuation blocks and raw fallback blocks.
- **Gotchas:** Moving blocks can accidentally change blank-line semantics, list continuation indentation, or frontmatter position. Frontmatter should remain document-start-only. Raw Markdown blocks should move as opaque units unless there is a parser-backed transformation.

## 2. Rich Markdown with lossless raw fallback

### Intention capture

- **What it can do:** Render common Markdown as rich interactive blocks while preserving unsupported or project-specific syntax as raw Markdown blocks/spans so files round-trip safely.
- **What it is useful for:** Supporting Obsidian-style notes, Forgejo/GitHub Markdown, static-site content, and house-specific Markdown conventions without requiring Velotype to fully understand every syntax variant.
- **When to use it:** When a Markdown document contains mixed normal content and uncommon syntax such as custom admonitions, embedded HTML, templating fragments, frontmatter, wikilinks, transclusions, or static-site shortcodes.
- **What it would not be useful for:** Transformations that require semantic understanding of unsupported syntax. Raw fallback preserves but does not deeply edit syntax.
- **Expected behavior / vignette:** John opens a note with YAML frontmatter, wikilinks, Markdown tables, and a site-specific shortcode. Velotype renders what it understands, preserves the shortcode as raw Markdown, and saving the document does not destroy the shortcode.
- **Surface it touches:** Markdown parser/importer, block records, inline parser, raw block rendering, serializer, extension config/HM options.

### Implementation details

- **Surfaces touched:** `src/editor/document.rs`, `src/components/*` block types, inline parsing in the components layer, preferences in `src/config/preferences.rs`, HM options in `nix/home-manager.nix`, and fixture tests.
- **Starting patterns/examples:** The existing frontmatter preservation and raw Markdown fallback behavior in `src/editor/document.rs`; HTML safety handling; table and Mermaid parsing as examples of syntax-specific handling with fallback.
- **Adaptation considerations:** Add extension flags as preferences first, but ensure the behavior is either actually gated or documented as preservation-only. New syntax should have parse -> serialize fixtures for valid, mixed, and invalid forms.
- **Gotchas:** “Lossless” means preserving exact user text where possible, including blank lines and spacing. Normalizing syntax can be useful, but should be opt-in. Invalid syntax is often more important to preserve than valid syntax because drafts are commonly incomplete.

## 3. Knowledge-management primitives

### Intention capture

- **What it can do:** Treat notes and blocks as linkable objects: wikilink completion, backlinks, unresolved link reports, block references, transclusions, embeds, task metadata, and note rename/link rewrite support.
- **What it is useful for:** Personal knowledge management, project notes, Zettelkasten-like workflows, Obsidian-compatible repositories, and cross-document navigation.
- **When to use it:** When editing a repository of interlinked Markdown files where the user cares about graph structure, note discovery, backlinks, and safe refactors.
- **What it would not be useful for:** Single throwaway Markdown files, prose that does not use links/tasks/frontmatter, or cases where a full external PKM app is the desired source of truth.
- **Expected behavior / vignette:** John types `[[net` in a project note. Velotype suggests `networking-plan.md` from the workspace. Activating the suggestion inserts `[[networking-plan|Networking plan]]`. A side panel shows backlinks to the current note, grouped by source document and block context.
- **Surface it touches:** Workspace indexing, LSP integration or internal indexer, completions, hover, side panels, document link parsing, rename operations.

### Implementation details

- **Surfaces touched:** Future workspace/project model, config preferences for knowledge features, editor completion/hover UI, document parsing for wikilinks/block refs, export/serialization, and potentially a background index service.
- **Starting patterns/examples:** Markdown-oxide can provide workspace intelligence for wikilinks/backlinks via LSP. Existing Velotype config/profile boundary can expose `[lsp.markdown]` or `[knowledge]` options. Existing raw wikilink preservation is the safe parsing baseline.
- **Adaptation considerations:** Start read-only: link completion, hover, backlinks, diagnostics. Mutating operations like rename/link rewrite need exact text edits and good conflict handling. Consider using LSP as workspace intelligence and Velotype blocks as the UI attachment layer.
- **Gotchas:** LSP positions are UTF-16 text positions, while Velotype has a block tree. Position mapping must be reliable before applying edits. File moves/renames require workspace-wide consistency. Avoid editor-specific metadata unless it serializes to portable Markdown conventions.

## 4. Repo-local asset workflows

### Intention capture

- **What it can do:** Manage pasted and linked media as first-class document assets: copy images to repo-local folders, generate safe names, keep links relative, detect missing files, preview dimensions, and batch move/rename assets with link updates.
- **What it is useful for:** Documentation repositories, notes with screenshots, PDFs exported from Markdown, and workflows where assets must remain portable in Git.
- **When to use it:** When creating or maintaining Markdown that includes screenshots, diagrams, scanned images, or visual references.
- **What it would not be useful for:** Remote image hosting workflows where assets live outside the repo, or highly specialized DAM/media-library needs.
- **Expected behavior / vignette:** John pastes a screenshot while editing `docs/research/foo.md`. Velotype copies the file to `docs/research/assets/foo-screenshot-1.png`, inserts `![foo screenshot](assets/foo-screenshot-1.png)`, and warns later if the file is deleted from disk.
- **Surface it touches:** Clipboard/image paste handling, document path awareness, asset path preferences, image block rendering, link rewrite utilities, diagnostics.

### Implementation details

- **Surfaces touched:** Existing image paste behavior in `src/editor/events.rs`, preferences in `src/config/preferences.rs`, HM options in `nix/home-manager.nix`, image block parsing/rendering, and export HTML/PDF base path handling.
- **Starting patterns/examples:** The existing `[images] asset_dir` and `naming` implementation, `copy_to_assets_folder` behavior, slug/counter tests, and relative image handling in export.
- **Adaptation considerations:** Keep paths document-relative in serialized Markdown. Add utilities for moving/renaming assets that update links. Make repo root detection configurable later if document folder is not the desired asset root.
- **Gotchas:** Symlinks, spaces/non-ASCII file names, duplicate names, documents outside a Git repo, and unsaved documents all need clear behavior. Avoid deleting assets automatically unless the user explicitly confirms.

## 5. Object-like tables, diagrams, code fences, and math

### Intention capture

- **What it can do:** Treat complex Markdown constructs as interactive objects: table row/column operations, Mermaid preview/source toggle, code fence language picker, math preview, and export-aware rendering controls.
- **What it is useful for:** Technical writing, architecture docs, runbooks, reports, and documents where Markdown structures are easier to edit through focused mini-tools.
- **When to use it:** When editing a table, diagram, or fenced block where raw Markdown syntax is awkward or error-prone.
- **What it would not be useful for:** Minimal prose editing or users who prefer raw source mode for every construct.
- **Expected behavior / vignette:** John focuses a Markdown table, presses “insert column right”, and Velotype updates every row including separators while preserving alignment style. For a Mermaid block, Velotype shows a rendered preview with a source toggle and export uses the rendered diagram path.
- **Surface it touches:** Block renderers, block-specific interaction handlers, parser/serializer, export rendering, keyboard commands, possibly embedded preview engines.

### Implementation details

- **Surfaces touched:** Table parsing/rendering modules, Mermaid component, code block handling, math handling, editor render/event code, export HTML/PDF renderers.
- **Starting patterns/examples:** Existing table region parsing in `src/editor/document.rs`; Mermaid support under `src/components/mermaid`; code fence parsing helpers; PDF/HTML export modules.
- **Adaptation considerations:** Each object should degrade to source editing. Keep syntax-specific operations localized to block-specific modules. Export should consume the same document model rather than a separate parser where possible.
- **Gotchas:** Markdown tables have ambiguous formatting, escaped pipes, multiline cells, and alignment markers. Mermaid rendering may require external assets or browser capabilities. Code fences can be nested or malformed and must remain round-trip safe.

## 6. Semantic commands and workflow transforms

### Intention capture

- **What it can do:** Provide commands based on document meaning: convert paragraphs to callout, extract section to new note, insert daily-note heading, toggle task state, collect TODO blocks, sort checklist by status, copy current section permalink, export current heading subtree.
- **What it is useful for:** Keyboard-driven knowledge work where common authoring operations are higher-level than editing text.
- **When to use it:** When the user repeatedly performs the same structural Markdown transformations across notes or docs.
- **What it would not be useful for:** One-off edits, arbitrary transformations without a stable convention, or transformations that require complex user-specific policy without configuration.
- **Expected behavior / vignette:** John selects three paragraphs and runs “Convert to callout: note”. Velotype wraps them in a Markdown callout, updates the block UI, and saving yields portable callout syntax. Later, “Export current section” produces a PDF for just that heading subtree.
- **Surface it touches:** Actions, command palette/which-key, selection model, document tree transforms, export, preferences/templates.

### Implementation details

- **Surfaces touched:** `src/components/actions.rs`, editor action handlers, selection/range utilities, document tree mutation APIs, export module for subtree export, config/HM options for templates and conventions.
- **Starting patterns/examples:** Existing actions and which-key grouping; existing export CLI and editor export paths; block movement/serialization tests once structural editing exists.
- **Adaptation considerations:** Commands should be small, typed, and testable. Prefer explicit command IDs so keybindings and which-key remain discoverable. For templates, keep Nix/HM-managed defaults but allow mutable user overrides.
- **Gotchas:** Workflow transforms can easily become hard-coded to one user. Keep policies in typed config and preserve default upstream behavior. Undo/redo support is essential before broad mutation commands feel safe.

## 7. LSP-backed Markdown intelligence

### Intention capture

- **What it can do:** Let Velotype act as an LSP client for Markdown tools such as markdown-oxide and/or Marksman, starting with diagnostics, hover, completion, document symbols, definitions, references, and backlinks.
- **What it is useful for:** Combining workspace intelligence from an external Markdown language server with Velotype's structured block UI.
- **When to use it:** In a repository of notes/docs where cross-file links, frontmatter, headings, and references matter.
- **What it would not be useful for:** Pure WYSIWYG editing without a workspace, or LSP features that require complex text edits before Velotype has robust text-position mapping.
- **Expected behavior / vignette:** John opens a note and Velotype starts `markdown-oxide` because `[lsp.markdown] enable = true`. Diagnostics appear attached to blocks; typing a wikilink shows workspace note completions; hovering a link shows target metadata; “go to definition” opens the target note.
- **Surface it touches:** Config/HM options, subprocess lifecycle, JSON-RPC/LSP protocol handling, document synchronization, diagnostics UI, completion/hover/navigation UI, workspace root detection.

### Implementation details

- **Surfaces touched:** New LSP client module, editor lifecycle, document serialization/change tracking, config preferences, HM module, action handlers for go-to-definition/references, and UI surfaces for diagnostics/completions.
- **Starting patterns/examples:** `lsp-types` for protocol data structures; `tower-lsp` is server-oriented but its types/patterns are useful; Zed/Helix demonstrate mature LSP UX; markdown-oxide provides the target server behavior. Velotype's headless CLI/config-profile work is a good model for typed, fail-soft configuration.
- **Adaptation considerations:** Phase it carefully:
  1. config and subprocess spawn;
  2. initialize/didOpen/didChange/didClose;
  3. publishDiagnostics attached to blocks;
  4. hover/completion/navigation;
  5. workspace edits/rename only after precise mapping exists.
- **Gotchas:** LSP uses UTF-16 line/character positions over plain text, while Velotype edits a block tree. For read-only features, serialized Markdown can be the source of truth. For code actions/rename/workspace edits, exact position mapping is mandatory to avoid corrupting documents. Server availability should be fail-soft with clear status, not an app startup failure.

## 8. Document policy and style linting

### Intention capture

- **What it can do:** Enforce or suggest repository/document conventions: one H1, required frontmatter keys, images under configured asset dirs, code fences with languages, valid wikilinks, task metadata, or house Markdown style.
- **What it is useful for:** Keeping project documentation consistent and making implicit writing rules visible at edit time.
- **When to use it:** In repos with conventions, published docs, team notes, or personal knowledge bases where consistency matters.
- **What it would not be useful for:** Freeform scratch notes where warnings are distracting, or documents intentionally using divergent syntax.
- **Expected behavior / vignette:** John opens a design note. Velotype shows non-blocking warnings: “missing frontmatter tag `status`”, “image path should be under `assets/`”, and “document has two H1 headings”. A quick-fix inserts the missing frontmatter key.
- **Surface it touches:** Diagnostics, config/HM policy options, parser/indexer, quick fixes, maybe LSP integration if diagnostics come from markdown-oxide or a custom checker.

### Implementation details

- **Surfaces touched:** Preferences/HM module for policy toggles, diagnostics model, document parser, image/link scanners, UI decorations, command/action quick fixes.
- **Starting patterns/examples:** Existing config preference patterns; raw/frontmatter preservation; image asset config; potential LSP diagnostics flow if markdown-oxide emits relevant diagnostics.
- **Adaptation considerations:** Policies should be opt-in and scoped by profile/repo. Severity levels should be configurable. Quick fixes should show exact resulting Markdown or be undoable.
- **Gotchas:** Overzealous linting can make Velotype feel hostile. Avoid blocking save/export by default. Some conventions conflict between GitHub, Obsidian, static site generators, and internal docs, so profiles matter.

## Cross-cutting implementation notes

- Preserve plain Markdown as the durable storage format.
- Prefer typed config/HM options over hard-coded John-specific behavior.
- Keep unsupported syntax lossless through raw fallback.
- Add round-trip tests for every parser/serializer change, including invalid/incomplete input.
- Start with read-only or reversible features before mutation-heavy workflows.
- Keep GUI behavior fail-soft when optional tools like language servers, Chromium, or renderers are missing.
- Expose commands through action metadata so keybindings and which-key stay discoverable.
