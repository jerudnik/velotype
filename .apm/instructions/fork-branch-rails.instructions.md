---
description: Fork branch rails and placement reminders for the Velotype fork.
applyTo: "**"
---

# Fork branch rails

When working in this forked upstream project, check the current branch before editing.

Durable rails:

- `vendor/upstream`: clean upstream import. Do not make downstream edits here. In this repo, create or document this rail only after verifying the original upstream URL and commit.
- `distro/nix`: reusable Nix packaging only: flake outputs, packages, apps, overlays, Home Manager modules, cache, and CI.
- `main`: stable custom fork. Put fork behavior, shims, compatibility fixes, and app features here.
- `stack/NN-topic`, `pr/topic`, or `exp/topic`: ordered review, upstream-PR, or disposable experiment work before folding into `main` or upstreaming.

Before changing files, run:

```sh
git branch --show-current
nix run github:jerudnik/4nix-utilities#fork-status   # rail health vs upstream
```

The full rail model, maintenance loop, and patch ledger live in
`docs/BRANCHING.md` and `docs/fork/patch-ledger.md`. Validate packaging hygiene
with `nix run github:jerudnik/4nix-utilities#fork-doctor`; reconcile a stale
local clone with `nix run github:jerudnik/4nix-utilities#fork-sync`.

Placement rule:

- Reusable app packaging, wrappers, overlays, and Home Manager modules belong in this fork.
- 4nix consumes this fork's outputs. It should not duplicate Velotype-owned packaging unless temporary, documented, and tracked for retirement.
- Use explicit remotes in durable docs and scripts: `upstream`, `github`, and `forgejo`. Treat `origin` as legacy/local state unless explicitly retained.
