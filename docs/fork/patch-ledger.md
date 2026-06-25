# Downstream patch ledger

Track downstream patches that may need to be upstreamed, watched, or retired.
Permanent fork behavior can stay here too, but every temporary shim must have a
retirement condition and validation command.

| Patch | Class | Status | Upstream ref | Retire condition | Validation |
|---|---|---|---|---|---|
| Crane Nix packaging (flake, package, HM module, Cachix, CI) | `distro(nix)` | `permanent-downstream` | none | Keep while upstream ships no Nix support. Reusable; may be offered upstream. | `nix build .#velotype && nix flake check` |
| Config directory + profile support | `feature(config)` | `reviewing` | none yet | Per-feature upstream review. | `nix build .#velotype` |
| Configurable keybinding profiles + which-key | `feature(keybindings)` | `reviewing` | none yet | Per-feature upstream review. | `nix build .#checks.x86_64-linux.hm-module` |
| Configurable image asset paste | `feature(images)` | `reviewing` | none yet | Per-feature upstream review. | `nix build .#velotype` |
| Frontmatter + wikilink round-trip preservation | `feature(markdown)` | `reviewing` | none yet | Upstream preserves frontmatter/wikilinks losslessly. | `cargo test` (round-trip) |
| Headless export CLI (`--export html|pdf`) | `feature(cli)` | `active` | none yet | Upstream adds an equivalent headless export path. | `velotype --export html in.md -o out.html` |
| Desktop entry + hicolor icon install | `distro(nix)` | `permanent-downstream` | none | Keep; Linux desktop integration for the Nix package. | `nix build .#checks.x86_64-linux.desktop-entry` |

Statuses:

- `local-only`
- `temporary-shim`
- `planned-upstream-pr`
- `submitted-upstream-pr`
- `waiting-upstream-release`
- `permanent-downstream`
- `reviewing`
- `active`
- `retire-candidate`
- `retired`
