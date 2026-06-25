---
description: Root agent contract for the Velotype fork.
applyTo: "**"
---

# Velotype agent contract

## Project purpose

- Velotype is a native Rust + GPUI Markdown editor maintained here as a patchable fork.
- This repository should remain consumable as a reusable Nix flake by downstream configs such as `4nix`.

## Fork conventions

Use this pattern for this fork and for future forked projects unless the user explicitly chooses a different shape.

### Reusable flake surface

- Treat fork-specific work as first-class, reusable flake surface area instead of one-off downstream glue.
- Preserve and extend reusable outputs when they matter: `packages`, `apps`, `overlays`, and `homeModules` / `homeManagerModules`.
- Prefer exposing wrappers, modules, and package variants from the fork itself rather than re-implementing them in downstream repositories.
- Keep flake output names stable and obvious: the default package/app should run the fork, and named outputs should be suitable for downstream imports.

### Downstream consumption

- Downstream repos should consume the fork as a flake input.
- Local patchable working copies should be consumed with `git+file://` flake inputs, as `4nix` does for this Velotype checkout.
- Downstream comments should explain how the fork is consumed and why the input exists, not duplicate implementation internals owned by this repo.
- If a downstream needs behavior that belongs to the fork, add or document the reusable output here first, then simplify the downstream wiring.

### Fork delta ownership

- Document fork-only behavior close to the owning source: package files, Home Manager modules, flake outputs, feature code, or `docs/fork-ledger.md`.
- Keep the delta from upstream legible. Prefer small, named wrappers/modules over hidden downstream patches.
- When borrowing a pattern from another fork, such as `jcode`, copy the reusable shape, not unrelated project-specific details.
- Avoid local-only generated client state in git unless the project explicitly decides to track it.

### Validation

- For Nix surface changes, run the smallest relevant `nix flake check`, package build, app run, or Home Manager module build that proves the reusable output works.
- When downstream consumption is part of the change, also validate the downstream-facing interface: output name, module import, overlay attr, or `git+file://` input path.

## Work guidance

- Before editing, inspect the nearest applicable generated `AGENTS.md` contract and any parent contract.
- Do not hand-edit generated agent surfaces. Edit `.apm/instructions/*.instructions.md`, `.apm/skills/*/SKILL.md`, or `apm.yml`, then regenerate with APM.
- Keep instructions concise, durable, and operational. Prefer contracts over diary notes.
- Avoid committing local-only generated client state unless the project explicitly decides to track it.

## Validation

- For APM source changes, run `apm compile --validate` when the APM CLI is available.
- For generated instruction changes, run `apm compile` and review generated surfaces for stale or contradictory guidance.
- For Nix surface changes, run the smallest relevant flake check or package/module build before reporting completion.

## Child DOX Index

- `.apm/AGENTS.md` — APM source-of-truth and generated-output ownership.
