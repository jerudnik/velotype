---
description: APM source ownership contract for this repository.
applyTo: ".apm/**"
---

# APM source contract

## Purpose

- `.apm/` owns agent-facing source primitives for this repository.
- APM compiles these primitives into client-specific generated surfaces.

## Ownership

- Edit `.apm/instructions/*.instructions.md` for shared instructions.
- Edit `.apm/skills/<name>/SKILL.md` for repo-local skills.
- Edit `apm.yml` for targets, dependencies, MCP declarations, includes, and scripts.
- Do not hand-edit generated outputs such as `AGENTS.md`, `GEMINI.md`, `.claude/rules/`, `.github/instructions/`, `.agents/skills/`, `.claude/skills/`, `.codex/`, `.gemini/`, or `.mcp.json`.

## Work guidance

- Keep primitives small and specific to stable repository behavior.
- Use front matter with `description` and `applyTo` on instruction primitives.
- If a generated agent surface contains useful ad-hoc instructions, import the durable parts into `.apm/` and regenerate.

## Verification

- Run `apm compile --validate` after editing primitives.
- Run `apm compile` after changing generated instructions.
- Run `apm install` after changing dependencies or MCP declarations.
