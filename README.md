# shed

The org-wide workshop for `must-show-your-work` (MSYW). Holds Claude's
state and notes about the org's repos, plus tooling that operates
across repos.

This repo is intentionally private — it carries process artefacts, not
math content. The math lives in sibling repos (`giyf`, eventually more
texts) and the supporting infrastructure in `atlas` (and others to
come).

## Layout

- `memory/` — Claude's persistent project memory. One file per topic,
  indexed by `memory/MEMORY.md`. Conventions for what to save live
  in the top-level `CLAUDE.md` system prompt.
- (planned) `manifest/` — west or vcstool manifest pinning the
  versions of sibling repos that the current MSYW state assumes.
- (planned) `templates/` — org-wide files (flake.nix, Justfile,
  .envrc, .env, common .gitignore) that new repos pull in via an
  install command.
- (planned) `tools/` — org-wide scripts: lint (cf. `project_giyf_unproven_lint.md`),
  build coordination, eventual homelab connectors.

## Memory and Claude

Memory was previously at `~/.claude/projects/-home-jfredett-rivendell-geometry-is-your-friend/memory/`.
It now lives here so it travels with the org. Until Claude's
config is pointed at this location (via `CLAUDE_CONFIG_DIR` or a
symlink), this directory is canonical but read-only from Claude's
perspective.
