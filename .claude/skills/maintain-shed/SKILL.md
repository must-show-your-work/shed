---
name: maintain-shed
description: Update the public-facing "prefab" of shed (flake.nix, flake.lock, lib/, README.md, .gitignore) and ship it to `must-show-your-work/shed` on GitHub. Use when Joe asks to "publish shed", "bump the shed flake", "update the lean-shell lib", "ship shed", or any time `flake.nix` / `flake.lock` / `lib/**` changed locally and downstream repos (giyf, atlas, …) need to see the new state. Local `main` always keeps the full working tree; the `publish` branch carries only the allowlisted subset.
---

# Maintain shed (publish cycle)

Shed has two faces:

- **Local `main`** — the full working tree (memory, BACKLOG, CLAUDE.md, forks docs, …). Never pushed.
- **Remote `main`** at `git@github.com:must-show-your-work/shed.git` — only the files needed for downstream Nix flake consumers (`flake.nix`, `flake.lock`, `lib/`, `README.md`, `.gitignore`). Sourced from the local `publish` orphan branch.

The split is enforced by `bin/shed-publish` — *not* by `.gitignore`. The script's `ALLOWLIST` is the source of truth for what ships.

## When to run

- A flake input bumped (`nix flake update <input>` produced a new `flake.lock`).
- `lib/lean-shell.nix` (or any future `lib/*`) changed.
- The public `README.md` changed.
- A new file needs to start shipping — first edit `bin/shed-publish`'s `ALLOWLIST` array, then publish.

Do NOT run it for changes to `memory/`, `BACKLOG.md`, `CLAUDE.md`, `bin/**`, `forks/**`, `sources/**`, or other local-only files; the script will detect "tree unchanged" and skip, but rule of thumb: if downstream Nix consumers wouldn't care, no publish needed.

## Procedure

1. **Verify local state.** Confirm working tree clean (`git status`) on `main`. Stash or commit anything in-flight before publishing — the script doesn't touch the working tree, but having uncommitted public-facing changes hidden in the worktree leads to surprises.

2. **Run the script.**

   ```bash
   cd /storage/code/must-show-your-work/shed
   bin/shed-publish
   ```

   Output cases:
   - `shed-publish: tree unchanged (…); nothing to commit` — nothing in the allowlist actually changed. Stop.
   - `shed-publish: publish ← <sha>` — a new commit was created on the `publish` branch. Continue.
   - `warning: allowlist entries missing from worktree:` — a required file is missing (someone deleted `flake.nix`? `lib/`?). Stop and investigate.

3. **Verify the published tree.**

   ```bash
   git ls-tree -r --name-only publish
   ```

   Output should match exactly the `ALLOWLIST` in `bin/shed-publish` (5 entries as of writing: `.gitignore`, `README.md`, `flake.nix`, `flake.lock`, `lib/lean-shell.nix`). If anything else appears — for example `sources/whatever.pdf` because someone added it to the allowlist — STOP and ask Joe. The point of the publish boundary is to keep copyrighted / private content from leaking.

4. **Push.** If the script said `pushed to origin:main`, you're done. If it printed `no remote 'origin'; commit is local only`, add the remote and re-publish:

   ```bash
   git remote add origin git@github.com:must-show-your-work/shed.git
   bin/shed-publish
   ```

5. **Notify downstream**. If a flake input bumped, the downstream consumers' `flake.lock` for the `shed` input still points at the old commit. Tell Joe to run `nix flake update shed` in each consumer repo (giyf, atlas, …) when convenient.

## Verify after publishing

```bash
bin/gh-mswy api /repos/must-show-your-work/shed/commits/main | head -3
```

The SHA in `"sha": "…"` should match what `git rev-parse publish` shows locally. If they diverge, the push didn't take or you're looking at a stale view.

## When NOT to use this skill

- Changes are local-only (memory, backlog, …). Just `git commit` on `main`.
- The change is in `bin/**` itself. Same — local-only, no publish needed.
- Joe says "bump the shed input in giyf" — that's the downstream side, handled by [[bootstrap-from-shed]] / direct `nix flake update`. The shed side only matters if shed itself has new content.

## Failure modes seen in the wild

- **`gh-mswy` 403 on org operations** — App lacks the permission. Surface to Joe; don't try to work around.
- **`--force-with-lease` rejected** — someone else pushed to `origin/main` (the publish branch) between local and remote. Fetch, rebase if appropriate, re-run. If the remote has unexpected content (e.g. someone pushed a different snapshot manually), STOP — Joe needs to reconcile.
- **`publish` branch deleted locally** — re-creating it is automatic: `bin/shed-publish` makes a fresh orphan commit, parented on nothing. Just rerun.
