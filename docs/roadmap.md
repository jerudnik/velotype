# Velotype Roadmap

## Vision

Velotype is a **minimalist, high-performance Markdown editor** built on a native Rust/GPUI block model. The goal is not to clone Obsidian or Notion — it is to provide a small set of **simple, composable tools** that can be chained together in powerful ways. Every feature is a discrete, understandable unit that stands on its own and composes with the rest.

### Design Principles

1. **Minimal surface, maximal leverage.** Each tool does one thing well and has a clear boundary. Users compose them, they don't hunt through feature menus.
2. **Native speed.** Rust + GPUI with zero WebView overhead. Rendering, parsing, search, and embed inference all run on the metal.
3. **Fail-soft everything.** Every optional capability (LSP, semantic search, embedding models) degrades gracefully. The editor opens and edits plain Markdown even when every optional system is absent.
4. **Portable data.** All metadata and annotations live in the Markdown file or a transparent JSON sidecar. No proprietary format. No lock-in. Git-diffable.
5. **Keyboard-first.** Every action is bound through the existing `WhichKey`/keybinding system. Mouse is available but never required.
6. **Configurable, not opinionated.** Themes, keybindings, language packs, and extension preferences all follow the same layered partial-override pattern. Defaults are sensible; everything is overridable.

---

## Feature Map

```
                    ┌──────────────────────────────┐
                    │      WORKSPACE PANEL          │
                    │  ┌──────────┐ ┌────────────┐  │
                    │  │  Files   │ │  Outline   │  │
                    │  └──────────┘ └────────────┘  │
                    │  ┌──────────┐ ┌────────────┐  │
                    │  │  Search  │ │ Annotations │  │
                    │  └──────────┘ └────────────┘  │
                    └──────────────────────────────┘
                                    │
            ┌───────────────────────┼───────────────────────┐
            ▼                       ▼                       ▼
    ┌──────────────┐       ┌──────────────┐       ┌──────────────┐
    │    SEARCH    │       │ ANNOTATIONS  │       │   METADATA   │
    │  ┌────────┐  │       │ ┌──────────┐ │       │ ┌──────────┐ │
    │  │Keyword │  │       │ │ Comments │ │       │ │  Block   │ │
    │  │(ripgrep)│  │       │ │ + Tags   │ │       │ │ Metadata │ │
    │  └────────┘  │       │ └──────────┘ │       │ └──────────┘ │
    │  ┌────────┐  │       │ ┌──────────┐ │       │ ┌──────────┐ │
    │  │Semantic│  │       │ │  Review  │ │       │ │ Outline  │ │
    │  │(ONNX)  │  │       │ │  Threads │ │       │ │ History  │ │
    │  └────────┘  │       │ └──────────┘ │       │ └──────────┘ │
    │  ┌────────┐  │       └──────────────┘       │ ┌──────────┐ │
    │  │Re-rank │  │                               │ │  Block   │ │
    │  │(ONNX)  │  │                               │ │Fingerprint│ │
    │  └────────┘  │                               │ └──────────┘ │
    └──────────────┘                               └──────────────┘
```

---

## 1. Workspace Keyword Search

### What it is

A third tab in the workspace side panel (`ctrl-shift-f`) that searches all Markdown files in the workspace directory for a keyword or regex pattern. Results show as clickable `file.md:line — context snippet` entries. Clicking opens the target file and scrolls to the match line.

### Why it matters

The workspace panel already lets you browse files and headings, but there is no way to find content by keyword. Users with dozens or hundreds of interlinked markdown notes need to jump directly to the paragraph that mentions a specific term, not just navigate a file tree.

### Implementation approach

- **Backend:** `ripgrep` subprocess via `tokio::process::Command` (already a dep). No new crate. Returns structured JSON. Respects `.gitignore` automatically.
- **Debounce:** 250ms after last keystroke before firing the search.
- **Results:** Streamed into the workspace panel. Each result shows filename, line number, and a context snippet with match highlighting.
- **Click action:** Reuses `open_workspace_file()` from the existing files tab, then scrolls to the matching block via `SourceTargetMapping`.
- **Config:** `[workspace.search]` in config.toml — `case_sensitive`, `max_results`, `exclude_patterns` (paths to skip).
- **Keybinding:** `ctrl-shift-f` → `ToggleWorkspaceSearch` action, `ShortcutCategory::Navigation`.

### Problems & Edge Cases

| Problem | Resolution |
|---|---|
| `rg` not on PATH | Fall back to a pure-Rust glob + `std::fs::read_to_string` + regex scan. Slower but always works. Show "ripgrep not found; using built-in search" badge. |
| Binary files in workspace | `rg --type md` or `-g '*.md'` flag; built-in fallback filters by extension. |
| Large workspace (10K+ files) | `rg` handles this natively. Built-in fallback adds a file-count cap (configurable: `max_files_scanned`). |
| Workspace root not set (unsaved file) | Search tab shows "Open or save a file to search its workspace." |

### Dependencies

None. Pure Rust + optional `rg` subprocess.

---

## 2. Semantic Search with Local Embedding + Re-Ranking

### What it is

An extension of keyword search that understands meaning. Block content is embedded into a 384-dimensional vector space using a local ONNX model. A search query is embedded and matched against stored vectors via cosine similarity. A second-stage re-ranker model scores the top candidates, producing results ordered by semantic relevance rather than keyword overlap.

### Why it matters

Markdown notes are often loosely structured — ideas span multiple sections, terminology varies, and the exact phrasing you used last week may not match the query you think of today. Semantic search finds "discussion of rendering performance" even when the block says "paint overhead per frame."

### Two-stage pipeline

```
Query: "how does block layout work"
   │
   ▼
Stage 1 — Embedding (bge-small-en-v1.5, 384-dim, ~33MB ONNX, CPU)
   → cosine_similarity against stored block embeddings
   → top-20 candidates by vector score
   │
   ▼
Stage 2 — Re-ranking (bge-reranker-base, ~110MB ONNX, CPU)
   → cross-encoder scores (query, document_text) for each candidate
   → top-5 results, ordered by semantic relevance
```

### Technology

- **`fastembed-rs`** (crates.io, Apache 2.0, ~900 GitHub stars): Pure Rust ONNX inference for embeddings and reranking. No Python, no PyTorch. Synchronous API (no Tokio needed). Models auto-downloaded from HuggingFace on first use.
- **Models:**
  - Default embedder: `BAAI/bge-small-en-v1.5` (384-dim, 33MB, fast CPU inference)
  - Upgrade embedder: `BAAI/bge-base-en-v1.5` (768-dim, 110MB, higher quality)
  - Default reranker: `BAAI/bge-reranker-base` (~110MB)
- **Storage:** JSON sidecar at `$WORKSPACE/.velotype/search-index.json`. 384-dim × 4 bytes = ~1.5KB per block. A 1000-block workspace = 1.5MB index.
- **Incremental indexing:** On file save, compute an MD5 hash of each block's text. Re-embed only changed blocks. Background `tokio` task.

### Architecture

```
src/search/
├── mod.rs            # SearchState, WorkspaceSearch Tab enum extension
├── embedder.rs       # fastembed-rs wrapper: TextEmbedding + TextRerank
├── index.rs          # JSON sidecar read/write, incremental update
└── query.rs          # Two-stage pipeline orchestration
```

- Feature-gated behind Cargo feature `semantic-search` (pulls in `fastembed`, `ort`, `tokenizers`).
- `[search.semantic]` config: `enable`, `model` (small/large), `max_blocks_indexed`, `rerank_candidates`.
- Embedding happens on a background thread. UI shows an indexing progress badge in the search tab.
- No GPU required — ONNX CPU inference with `ort` is fast enough for sub-second responses on a modern laptop.

### Problems & Edge Cases

| Problem | Resolution |
|---|---|
| First-time model download | Show progress bar; models cached in OS config dir under `velotype/models/`. App works normally during download (search just returns "indexing in progress"). |
| Model download fails (offline, firewall) | Semantic search tab shows "Models unavailable — keyword search still works." No crash. |
| Workspace with 10K+ blocks | Cap at configurable limit (default 5000). Show "X blocks indexed out of Y total." |
| CPU spike during indexing | Rate-limit to one embed batch per 500ms. Background priority via `tokio::task::spawn_blocking`. |
| Index drift (file edited outside Velotype) | On file open, compare stored MD5 against current block texts. Re-index stale entries. |
| Out of memory on low-RAM machines | The 33MB embedder model is the floor. `max_blocks_indexed` can cap RAM to ~30MB (33MB model + 15MB for 5000 blocks × 384-dim × 4 bytes). |

### Dependencies

`fastembed` (with `ort`, `tokenizers` as transitive), gated behind Cargo feature flag.

### Config

```toml
[search.semantic]
enable = false                    # Opt-in; model download on first use
model = "small"                   # "small" (384-dim, 33MB) or "large" (768-dim, 110MB)
max_blocks_indexed = 5000         # Cap total indexed blocks per workspace
rerank_candidates = 20            # How many candidates the reranker scores
debounce_ms = 300                 # Debounce before embedding the query
```

---

## 3. Block Annotations (Comments, Tags, Review Threads)

### What it is

Inline annotations attached to specific blocks or text ranges within a block. Comments, tags, review status markers, and threaded discussions that travel with the Markdown file, not a separate database.

### Why it matters

A document evolves from outline → draft → review → polished prose. At each stage, different metadata is attached: "needs citation," "verify this claim," "move to section 3," "approved." Without structured annotations, this information lives in loose `%%comments%%` or external notes that drift out of sync.

### Annotation model

Three annotation types, all stored as Markdown-native reference links:

#### Inline comment (attached to a text span within a block)

```markdown
Velotype is a native Markdown editor built with Rust and GPUI.[](comment-a1b2)

[comment-a1b2]: # "type=comment; text=Cite performance benchmarks here; author=john; date=2026-06-27; status=open"
```

Rendered: a small colored dot or underline marker on the anchored text. Hover to read the comment. Resolve/reply inline.

#### Block-level tag/metadata (attached to an entire block)

```markdown
## Architecture Decisions[](tag-3c4d)

This section describes why we chose GPUI over a WebView approach.

[tag-3c4d]: # "type=meta; status=draft; tags=architecture,decision-record; created=2026-06-15"
```

Rendered: a subtle badge or icon in the block's left gutter showing status and tags. Click to view/edit metadata.

#### Review thread (threaded conversation on a block)

```markdown
The editor uses a native block tree as its runtime model.[](review-5e6f)

[review-5e6f]: # "type=thread; messages=[{author:alice,date:...,text:Is this still accurate for v0.7?},{author:bob,date:...,text:Yes, confirmed.}]; resolved=false"
```

Rendered: a comment bubble icon with unread count. Click to open the thread panel. Resolve to archive.

### Storage: why Markdown-native reference links

| Approach | Portability | Git-diff | Human-readable | Queryable |
|---|---|---|---|---|
| **Reference links (chosen)** | ✅ Valid Markdown everywhere | ✅ Footer-only changes | ✅ Self-documenting | ✅ Grep + structured parse |
| HTML comments `<!-- -->` | ⚠️ Some tools strip them | ⚠️ Inline noise | ⚠️ Hidden from preview | ✅ |
| JSON sidecar only | ❌ File separation | ❌ Binary/semi-structured | ❌ Need tooling | ✅✅ |
| Proprietary format | ❌❌ | ❌ | ❌ | ✅ |

The reference-link model keeps annotations in the file as invisible anchors + a structured footer section. In any Markdown viewer, the footnotes render as non-functional `#` links — the document is clean. In Velotype, the editor parses the footer, attaches annotations to blocks via the existing `SourceTargetMapping`, and renders inline markers.

### Implementation

```
src/annotations/
├── mod.rs            # AnnotationState, types
├── parse.rs          # Parse reference-link footer into Annotation structs
├── serialize.rs      # Serialize back to Markdown footer
├── render.rs         # Inline markers, hover tooltips, gutter badges
└── panel.rs          # Annotations tab in workspace panel (list/filter/resolve)
```

- Workspace panel gains an **Annotations tab** showing all annotations across the workspace: grouped by file, filterable by type/status/tag/author.
- Click an annotation → opens file + scrolls to the annotated block.
- `WhichKey` actions: `AnnotateSelection`, `ToggleAnnotationPanel`, `ResolveAnnotation`, `AddTag`.
- The Markdown importer in `document.rs` already preserves unrecognized syntax as `RawMarkdown` blocks. The annotation footer requires a new pass: detect the footer section, parse it, strip it from rendered output, attach parsed annotations to blocks by UUID/position.
- Ghost anchors `[](id)` are zero-width — they don't affect rendered text layout.

### Config

```toml
[annotations]
enable = true                     # Parse and render annotations
show_inline_markers = true        # Dots/badges in the editor gutter
show_resolved = false             # Hide resolved comments by default
author_name = ""                  # Default author for new annotations (empty = OS username)
```

### Problems & Edge Cases

| Problem | Resolution |
|---|---|
| Anchor drift after editing | Anchors reference stable block UUIDs, not byte positions. When a block is deleted, orphaned annotations move to an "orphaned" section in the footer. |
| Footer bloat with many annotations | Footer is collapsible. "Clean" command strips resolved annotations. Old resolved threads auto-archive after 30 days. |
| Merge conflicts in footer | Footer is line-based `[id]: # "..."` entries. Standard git merge handles this — each entry is one line. |
| Annotations from other tools (Obsidian, etc.) | Only parse entries with recognized `type=` keys. Unknown entries are preserved but invisible. |
| Performance with 1000+ annotations | Parse footer once on file open. Annotations are in-memory `BTreeMap<BlockUuid, Vec<Annotation>>`. O(log n) lookup. |

### Dependencies

None. Pure Rust with existing `serde_json` for the footer value encoding.

---

## 4. Block Metadata Store (JSON Sidecar)

### What it is

A lightweight JSON file at `$WORKSPACE_ROOT/.velotype/blocks-index.json` that stores machine-generated metadata for every block in the workspace. This is separate from human-authored annotations (which live in the Markdown file itself) and holds data that would pollute the document: embedding vectors, edit timestamps, content hashes, outline snapshots, and computed properties.

### Why it matters

Annotations belong in the Markdown file — they are authored content. But embedding vectors, content fingerprints, and edit history are machine artifacts. Putting them in the `.md` file adds megabytes of invisible noise. A sidecar keeps the document clean while enabling search, history, and analysis features.

### Schema

```jsonc
{
  "version": 1,
  "workspace_root": "/home/john/notes",
  "indexed_at": "2026-06-27T14:30:00Z",
  "files": {
    "projects/velotype-architecture.md": {
      "md5": "d41d8cd98f00b204e9800998ecf8427e",
      "indexed_at": "2026-06-27T14:30:00Z",
      "block_count": 47,
      "blocks": {
        "a1b2c3d4-...": {
          "kind": "Heading",
          "level": 2,
          "text_hash": "e99a18c428cb38d5f260853678922e03",
          "text_preview": "Architecture Decisions",
          "source_range": [0, 84],
          "children": ["uuid-1", "uuid-2"],
          "embedding_384": [0.012, -0.034, ...],
          "metadata": {
            "created_at": "2026-06-15T10:00:00Z",
            "modified_at": "2026-06-27T14:25:00Z",
            "word_count": 3,
            "char_count": 22
          }
        }
      },
      "outline_snapshots": [
        {
          "timestamp": "2026-06-15T10:00:00Z",
          "headings": [
            {"text": "Architecture Overview", "level": 1},
            {"text": "Block Model", "level": 2}
          ]
        }
      ]
    }
  }
}
```

### Operations

- **On file open:** Load sidecar entries for this file. Compare MD5 — if changed, mark blocks for re-index.
- **On file save:** Update MD5, re-embed changed blocks, append outline snapshot. Write sidecar atomically (`write temp → rename`).
- **On workspace scan:** Discover all `.md` files, load sidecar, identify new/deleted/moved files.
- **On block edit:** The editor already fires `BlockEvent` for every mutation. A background task debounces and writes incremental updates.

### Size estimates

| Workspace size | Blocks | Sidecar size (w/ 384-dim embeddings) |
|---|---|---|
| Small (50 files, personal notes) | ~500 | ~750KB |
| Medium (200 files, project docs) | ~2,000 | ~3MB |
| Large (500 files, knowledge base) | ~5,000 | ~7.5MB |
| Very large (2000 files, org docs) | ~20,000 | ~30MB |

For workspaces exceeding the `max_blocks_indexed` config cap, embeddings are omitted and only metadata is stored.

### Problems & Edge Cases

| Problem | Resolution |
|---|---|
| Sidecar gets deleted | Rebuild from scratch on next file open. Search is temporarily unavailable during rebuild. |
| Sidecar gets out of sync (external edits) | MD5 mismatch triggers re-index on file open. |
| Multiple Velotype windows writing simultaneously | File-level advisory lock via `fs2`. Second writer waits or skips. |
| Sidecar grows too large | Configurable `max_sidecar_size_mb`. Beyond limit, drop oldest outline snapshots and LRU embeddings. |
| Moving/renaming files in workspace | Sidecar entries keyed by relative path from workspace root. On workspace scan, detect moved files by content hash matching. |

### Dependencies

`serde_json` (already a dep). Optional `fs2` for file locking. Optional `md5` or `sha2` for content hashing.

---

## 5. Outline Evolution Tracking

### What it is

The workspace outline tab already shows the current heading tree of the active document. With the sidecar metadata store, Velotype can also show how the outline has evolved over time — which sections grew, which were reorganized, and how the document's structure changed between saves.

### Why it matters

Long-form writing (essays, documentation, research reports) starts as an outline and fills in over time. Tracking this progression helps writers understand their own process, identify stagnant sections, and see at a glance what's changed since the last review.

### Features

- **Outline diff:** In the outline tab, toggle "Show changes since last save." New headings appear in green, removed in red, modified (same position, different text) in yellow.
- **Growth indicators:** Next to each heading, show `+N words` or `+M blocks` since the last snapshot.
- **Snapshot timeline:** A small timeline scrubber at the bottom of the outline tab. Drag to see the outline at any previous save point.
- **Stagnation warnings:** Headings unchanged for N saves (configurable) get a subtle "stale" indicator.

### Implementation

- Outline snapshots stored in the JSON sidecar: `outline_snapshots: [{timestamp, headings: [{text, level, block_uuid, word_count}]}]`.
- Diff computed on outline tab activation. Cheap — snapshot is a small Vec of heading structs.
- Timeline rendering reuses the existing GPUI tree widget with optional color overrides per node.

### Config

```toml
[workspace.outline]
show_evolution = true
snapshot_on_save = true
max_snapshots = 50           # Rolling window; oldest dropped when exceeded
stagnation_threshold_saves = 10
```

### Dependencies

None. Pure data structure diff on existing sidecar.

---

## 6. Block Fingerprinting & Content-Addressed Identity

### What it is

Each block gets a stable content hash (`md5(serialized_markdown)` or similar) stored in the sidecar. This enables: detecting when a block's content has actually changed (vs. just being re-parsed), finding duplicate or near-duplicate blocks across files, and tracking block movement (copy/paste between documents).

### Why it matters

As a workspace grows, the same information appears in multiple places — a definition repeated in several notes, a code snippet pasted into a tutorial and a reference doc. Content-addressed identity makes this visible. It also enables precise incremental indexing: only re-embed blocks whose content hash changed.

### Features

- **Duplicate detection:** In the search/annotations panel, show "This block also appears in file.md and other.md."
- **Change tracking:** "This block was modified 3 saves ago. Previous content: ..."
- **Move detection:** When a block is cut from file A and pasted into file B, the content hash reveals it's the same block, preserving its metadata history.

### Dependencies

`md5` or `sha2` crate for hashing. Trivial.

---

## Composition: How These Tools Chain Together

The power of this design is not in any individual feature — it's in how they compose:

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│  1. You write an outline in Velotype.                   │
│     → Each heading is a block with metadata.            │
│                                                         │
│  2. You draft sections over several sessions.           │
│     → Outline snapshots track structure evolution.      │
│     → Block fingerprints detect which sections changed. │
│                                                         │
│  3. You tag blocks needing review.                      │
│     → Annotations panel shows all "needs-review" blocks │
│       across the workspace.                             │
│                                                         │
│  4. You search for related content.                     │
│     → Keyword search finds exact matches.               │
│     → Semantic search finds conceptually related blocks │
│       even with different wording.                      │
│                                                         │
│  5. You share the document with a collaborator.         │
│     → They open it in any Markdown editor.              │
│     → Annotations appear as invisible reference links.  │
│     → They add review comments using the same syntax.   │
│                                                         │
│  6. You review feedback in Velotype.                    │
│     → The annotations tab groups comments by author.    │
│     → Resolving a thread marks it in the footer.        │
│     → "Clean" strips resolved annotations.              │
│                                                         │
│  7. You publish the final document.                     │
│     → HTML/PDF export (already exists) strips all       │
│       annotation markers automatically.                 │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

No single step requires understanding the whole system. Each tool is simple enough to learn in minutes. The chain emerges from using them together.

---

## What Velotype Is Not

- **Not a PKM system.** No graph view, no daily notes plugin, no spaced repetition. Those are apps. Velotype is an editor.
- **Not a Notion clone.** No databases, no formulas, no kanban boards. Velotype edits Markdown files, not structured documents.
- **Not a collaborative editor.** No real-time sync, no CRDTs, no cloud storage. Annotations enable async review workflows, not simultaneous editing.
- **Not an IDE.** LSP integration (already designed) is for Markdown intelligence, not code intelligence. IWE provides wikilink completion and backlinks — that's the ceiling.

---

## Implementation Phases

### Phase 0 — Foundation (already complete)
- Block model, rendered/source editing, workspace panel, export, theming, i18n, keybindings, IWE LSP design

### Phase 1 — Workspace Search + Sidecar
- Keyword search tab in workspace panel (ripgrep + built-in fallback)
- JSON sidecar metadata store (`$WORKSPACE/.velotype/blocks-index.json`)
- Block fingerprinting (content hashing)
- Outline snapshots on save
- Config: `[workspace.search]`, `[workspace.outline]`

### Phase 2 — Annotations
- Reference-link annotation model (comments, tags, review threads)
- Inline markers and hover tooltips
- Annotations tab in workspace panel
- "Clean" command to strip resolved annotations
- Config: `[annotations]`

### Phase 3 — Semantic Search
- `fastembed-rs` integration behind feature flag `semantic-search`
- Two-stage pipeline: embedding + reranking
- Background indexing with progress indicator
- Search tab extended with "Semantic" toggle
- Config: `[search.semantic]`

### Phase 4 — Polish
- Outline evolution diff view
- Duplicate block detection
- Stagnation warnings
- Performance tuning for large workspaces

---

## Config Surface (Complete)

```toml
[workspace.search]
case_sensitive = false
max_results = 50
exclude_patterns = [".git", "node_modules", "target"]
max_files_scanned = 5000

[search.semantic]
enable = false
model = "small"               # "small" | "large"
max_blocks_indexed = 5000
rerank_candidates = 20
debounce_ms = 300

[annotations]
enable = true
show_inline_markers = true
show_resolved = false
author_name = ""

[workspace.outline]
show_evolution = true
snapshot_on_save = true
max_snapshots = 50
stagnation_threshold_saves = 10
```

---

## Keybinding Surface (Proposed Additions)

| Action | Default Keys | Category |
|---|---|---|
| `ToggleWorkspaceSearch` | `ctrl-shift-f` | Navigation |
| `ToggleAnnotationsPanel` | `ctrl-shift-a` | Navigation |
| `AnnotateSelection` | `ctrl-/` | Edit |
| `ResolveAnnotation` | `ctrl-shift-enter` | Edit |
| `AddTag` | `ctrl-t` | Formatting |
| `ToggleOutlineEvolution` | (unbound) | Navigation |

All follow the existing `ShortcutDefinition` pattern in `src/components/actions.rs` and are configurable per-keybinding-profile.

---

## Nix Surface

Each feature that introduces optional runtime dependencies follows the same pattern as the IWE LSP design:

```nix
# Search: ripgrep is already in nixpkgs, no wrapping needed.
# Semantic search: models auto-download at runtime.

# Annotations: pure Markdown, no runtime dep.

# If optional tool wrapping is desired:
programs.velotype = {
  enable = true;
  search.keyword.ripgrepPackage = pkgs.ripgrep;  # optional explicit path
};
```
