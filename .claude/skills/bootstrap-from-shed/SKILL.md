---
name: bootstrap-from-shed
description: Wire a workspace repo (giyf, atlas, future MSYW projects) to consume shed as a Nix flake input so it can use `shed.lib.mkLeanShell` for its devshell. Use when Joe says "set up the devshell from shed", "wire <repo> to shed", "bootstrap a new MSYW repo", or when a new sibling repo is created that needs the standard Lean dev environment. Covers both local-development (`path:..`) and CI / fresh-clone (`github:must-show-your-work/shed`) setups.
---

# Bootstrap a repo from shed

The MSYW workspace standardizes its Lean devshell on a single helper, `shed.lib.mkLeanShell`. Every workspace repo (`giyf`, `atlas`, future titles) consumes it as a Nix flake input. The published `must-show-your-work/shed` repo carries only the files a fresh CI runner needs (`flake.nix`, `flake.lock`, `lib/`); the local working tree carries everything but is not visible to the world.

## Two consumption modes

A workspace repo has *two* ways to point its `shed` flake input. Always wire both as compile-time alternatives — your local dev loop should iterate against in-flight shed changes, but CI runners and prospective collaborators have to fetch shed from GitHub.

### Mode A — local development (host-only)

```nix
# flake.nix
inputs.shed.url = "path:/storage/code/must-show-your-work/shed";
```

Pros: edits to `shed/lib/lean-shell.nix` take effect on the next `nix develop` with no publish step.

Cons: hardcoded absolute path; doesn't work on any other machine; **breaks CI** because the runner has no `/storage/code/...` tree.

### Mode B — CI / fresh-clone (canonical)

```nix
# flake.nix
inputs.shed.url = "github:must-show-your-work/shed";
```

Pros: works on every host. The `flake.lock` pins a specific commit so the build is reproducible.

Cons: changes to shed need a publish (see [[maintain-shed]]) before downstream `nix flake update shed` picks them up.

## Procedure for a new workspace repo

1. **Add the input** in the consumer's `flake.nix`:

   ```nix
   {
     inputs = {
       shed.url = "github:must-show-your-work/shed";
       nixpkgs.follows = "shed/nixpkgs";
       flake-parts.follows = "shed/flake-parts";
       # nixpkgs-python is separate from shed because shed's base shell
       # uses whatever python3 nixpkgs ships; consumers that need 3.13
       # exactly pin it directly.
     };

     outputs = { self, nixpkgs, flake-parts, shed, ... } @ inputs:
       flake-parts.lib.mkFlake { inherit inputs; } {
         systems = [ "x86_64-linux" "aarch64-darwin" ];
         perSystem = { system, pkgs, ... }: {
           devShells.default = shed.lib.mkLeanShell {
             inherit pkgs system;
             extraPackages = with pkgs; [ /* repo-specific tools */ ];
           };
         };
       };
   }
   ```

2. **Lock and verify.**

   ```bash
   nix flake lock        # creates flake.lock; resolves shed → a specific SHA
   nix develop           # smoke-test the resulting shell
   ```

   If `nix flake lock` complains about a missing `shed/...` follow, the input wasn't picked up — check spelling and that `shed.url` is set before the `follows` lines reference it.

3. **CI integration.** Add an Actions workflow that:
   - uses `cachix/install-nix-action` with `accept-flake-config = true` so the project's `nix.conf` extras (substituters, trusted keys) take effect.
   - caches `.lake/` keyed by `lake-manifest.json`.
   - drops into `nix develop -c just <pipeline-target>`.

   Use giyf's `.github/workflows/pages.yml` as the reference workflow — it's the load-bearing pattern.

4. **Bumping the shed pin**. When `must-show-your-work/shed` ships a new prefab snapshot (see [[maintain-shed]]), each consumer needs to pick it up:

   ```bash
   nix flake update shed
   nix develop   # confirm nothing broke
   git add flake.lock && git commit -m "flake: bump shed"
   git push
   ```

   Don't bump if the shed prefab tree didn't actually change (the `publish: <timestamp>` commits are content-addressed via tree hash — `bin/shed-publish` only commits when the tree differs).

## When NOT to use this skill

- Existing consumer just needs a flake-lock refresh — that's a one-line `nix flake update shed`, not a wiring task.
- The change you're making is to `shed/lib/lean-shell.nix` itself — that's [[maintain-shed]]'s territory; this skill is only for the consumer side.
- Repo doesn't actually need a Lean devshell (pure docs / scripts repo) — wire it differently (or not at all).

## Verification

After bootstrap or a bump:

```bash
nix develop --command bash -c 'command -v lake && command -v lean'
```

Both should resolve to nix-store paths. If `lake` resolves but `lean` doesn't (or vice versa), the devshell composition broke — usually a `mkLeanShell` arg mismatch. Check the consumer's `extraPackages` for accidental overrides.

## Failure modes

- **`error: getting status of '/storage/.../shed'`** in CI — the consumer is still on Mode A (`path:...`). Switch to Mode B and re-lock.
- **`error: attribute 'mkLeanShell' missing`** — shed's published flake doesn't export `lib.mkLeanShell` for the current system. Either the publish dropped `lib/`, or shed's `flake.nix` was edited to change the output shape. Inspect `must-show-your-work/shed` directly: `bin/gh-mswy api /repos/must-show-your-work/shed/contents/flake.nix --jq .content | base64 -d`.
- **`flake-parts` version mismatch warnings** when a consumer also depends on Mathlib (which pins its own flake-parts) — `follows` chain needs care; Mathlib should be required *after* shed so its pins win. See giyf's `lakefile.lean` for the established ordering.
