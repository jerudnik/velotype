# Velotype architecture feasibility spikes

This report records low-risk probes for the addressable-block / optional-layer
writing-workbench direction. The probes intentionally avoid broad product-code
changes. They combine current-code inspection with a small text-level harness in
`tools/feasibility/block_layer_probe.py`.

## Fixture

`docs/feasibility/probe.md` contains:

- a heading;
- hidden `<!-- velotype:comment ... -->` scaffolding;
- a paragraph with Pandoc citations;
- an outline TODO list;
- hidden `<!-- velotype:todo ... -->` scaffolding;
- a final paragraph with author-suppressed citation syntax.

The probe harness can:

- split Markdown into coarse blocks;
- fingerprint blocks;
- reconcile a sidecar annotation after edits/moves;
- extract Pandoc-like citekeys;
- apply layer export policies: `omit`, `render`, `preserve`, `fail`.

## Spike 1: stable block identity

**Method:** Generate fingerprints for coarse Markdown blocks in the fixture.

**Observed result:** The fixture produced seven coarse blocks. Fingerprint-based
identity works for exact content, but edited text changes the fingerprint.

**Verdict:** Feasible only if Velotype distinguishes runtime identity, durable
identity, and content fingerprints. Fingerprints are useful reconciliation aids,
not sufficient durable IDs.

**Unlocks:** Block refs, comments, annotations, backlinks, review state.

**Hard decisions:** Durable IDs should probably be lazy and need-driven. Default
storage is still open: inline anchor, HTML comment, property block, or sidecar.

**Next step:** Prototype a `BlockAnchor` design with fields for runtime UUID,
optional durable ID, source range, canonical range, and content fingerprint.

## Spike 2: sidecar reconciliation

**Method:** Attach a sidecar annotation to a paragraph fingerprint, then edit the
paragraph and move another block. Reconcile by exact fingerprint, falling back to
token overlap.

**Observed result:** Exact fingerprint failed after text edit, but fuzzy token
matching reattached the annotation to the edited paragraph with score `0.857`.

**Verdict:** Feasible, but only with a layered reconciliation strategy. Source
spans alone will drift, fingerprints alone break on edits, and fuzzy matching
needs thresholds plus conflict UX.

**Unlocks:** Hidden comments, annotations, review notes, sidecar state.

**Hard decisions:** Sidecar location and conflict behavior. Need policy for
ambiguous matches, deleted blocks, and external edits.

**Next step:** Build a real source-map-backed reconciliation test around
Velotype's parser once block source spans are first-class.

## Spike 3: Pandoc citation preservation

**Method:** Extract citation-like tokens from fixture Markdown containing
`[@smith2020; @doe-2021]` and `[-@miller2022]`.

**Observed result:** Probe found `@smith2020`, `@doe-2021`, and `@miller2022`.
Research also showed Pandoc citation syntax is the right compatibility target,
with Zotero + Better BibTeX as a known-good bibliography workflow.

**Verdict:** Very feasible as a preservation and diagnostics feature. Native
rendering can wait.

**Unlocks:** Citation diagnostics, citekey completion, bibliography-aware writing,
Pandoc export.

**Hard decisions:** Whether Velotype owns a bibliography index or delegates to
external tools/LSPs. Whether preview comes from Pandoc, hayagriva/citum, or is
omitted initially.

**Next step:** Add focused round-trip tests for Pandoc citation syntax and a
small `.bib` citekey scanner prototype.

## Spike 4: layer policy export

**Method:** Apply policy vocabulary to fixture layer comments:

- `omit` removes `velotype:` scaffolding;
- `render` turns it into visible note callouts;
- `preserve` leaves raw comments;
- `fail` exits when layered metadata is present.

**Observed result:** `omit` removed Velotype layers, `render` emitted `[!NOTE]`,
`preserve` kept comments, and `fail` rejected the fixture.

**Verdict:** The vocabulary is feasible and useful. It should become an explicit
export concept before richer layers land.

**Unlocks:** Clean Markdown export, review export, debug export, CI enforcement.

**Hard decisions:** Per-target defaults and whether policies apply globally or by
layer type.

**Next step:** Define `LayerExportPolicy = omit | render | preserve | fail` in a
planning doc or small internal type before product implementation.

## Spike 5: hidden annotation UI feasibility

**Method:** Inspect current UI/editor seams.

**Observed result:** Current code already has relevant affordances:

- `BlockRecord::Comment` preserves visible HTML comment blocks as raw fallback;
- workspace drawer toggling exists;
- which-key and keybinding infrastructure exists;
- block rendering already has focused panels and inline interaction bounds;
- editor events route block-level interactions upward.

**Verdict:** Feasible for a minimal built-in UI. The easiest path is not a full
review system. Start with a side/workspace pane listing annotations anchored to
blocks, plus show/hide rendering for inline markers.

**Unlocks:** Comments, review notes, unresolved questions, writing scaffolding.

**Hard decisions:** How annotations are anchored and persisted. Whether hidden
annotations have inline markers, gutter markers, side panel entries, or all three.

**Next step:** Prototype a read-only annotation side panel backed by a static
sidecar/fixture before allowing edits.

## Spike 6: workflow extension registry

**Method:** Inspect action/keybinding/config seams and current extension docs.

**Observed result:** Velotype has GPUI action definitions, resolved keybindings,
which-key metadata, config-driven preferences, menu dispatch, workspace drawer,
and feature flags. Research lane concluded typed built-in seams are a better
near-term fit than dynamic Rust plugins.

**Verdict:** Feasible as a typed internal registry. Dynamic plugin ABI is not a
near-term requirement and would be premature.

**Unlocks:** Citation diagnostics, TODO scanner, side-panel providers, export
adapters, Markdown feature modules.

**Hard decisions:** Registry shape and hook boundaries. Need to avoid generic
plugin marketplace posture.

**Next step:** Define a `workflow_extensions` concept with command providers,
diagnostic providers, side-panel providers, Markdown feature flags, indexers, and
external process adapters.

## Spike 7: headless export with external tool path

**Method:** Inspect current CLI and flake outputs.

**Observed result:** Current branch already supports `velotype --export html|pdf`
with `--output` and `--theme`. Flake exposes package/app surfaces and can add
named export wrappers. Heavy external tools such as Pandoc/Typst can be optional
Nix app/package variants rather than default GUI dependencies.

**Verdict:** Feasible. Keep native export as the visual-fidelity lane. Add a
separate external-tool lane later for Pandoc/Typst/LaTeX handoff.

**Unlocks:** Academic/export pipeline, clean artifacts, CI document generation,
layer-policy enforcement.

**Hard decisions:** Source of truth for external export: raw Markdown, normalized
Markdown, runtime tree, or export AST. Need layer policies before serious handoff.

**Next step:** Add a named Nix app/wrapper prototype such as
`apps.${system}.velotype-pandoc-export` that includes Pandoc on PATH and delegates
clean Markdown export through a documented command.

## Overall verdict

All seven avenues are feasible enough to continue. The biggest architectural
unknown is not whether Velotype can support the vision. It is **how to represent
and reconcile optional layers without polluting Markdown or losing anchors after
external edits**.

The next highest-leverage prototype is a real block anchor + sidecar
reconciliation test using Velotype parser/source mappings rather than the coarse
text-level probe.
