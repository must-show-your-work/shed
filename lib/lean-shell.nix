{ pkgs
, system
, nixpkgs
, lean4-nix
, manifest ? import ./lean-toolchain-manifest.nix
, extraPackages ? []
, extraShellHook ? ""
, name ? "lean shell"
}:
let
  leanToolchain = pkgs.callPackage "${lean4-nix.outPath}/lib/toolchain.nix" {};
  leanBin = leanToolchain.fetchBinaryLean manifest;
  leanOverlay = final: prev: { lean = leanBin; };
  pkgsLean = import nixpkgs {
    inherit system;
    overlays = [ leanOverlay ];
  };
  # Native-extension run-time loader path. Python packages that ship
  # a C++ shared object (kuzu's `_kuzu.so`, etc.) need libstdc++ at
  # dlopen time; without this they fail with
  # `libstdc++.so.6: cannot open shared object file`. Same role as
  # the workspace devShell's `runtimeLibs`.
  runtimeLibs = [ pkgs.stdenv.cc.cc.lib ];
in
pkgsLean.mkShell {
  inherit name;

  packages = [
    pkgsLean.lean
    pkgs.elan
    pkgs.git
    pkgs.just
  ] ++ extraPackages;

  shellHook = ''
    # ANG-642: prepend lean4-nix-built bin so it wins over any
    # `lean4-elan-stub` shim inherited from an outer shell. The stub's
    # `readlink -f $0` + PATH-strip self-loop fork-bombs when invoked
    # under nix-develop, pinning CPU with no output. Load-bearing.
    export PATH="${pkgsLean.lean}/bin:$PATH"

    # Run-time loader path — see `runtimeLibs` above.
    export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath runtimeLibs}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

    # Atlas tooling — make `atlas` resolvable as a bare command in any
    # project that depends on atlas (via Lake). Three resolution
    # strategies, in order of accuracy:
    #   1. `lake-manifest.json` — `.packages[].dir` for the atlas entry
    #      reflects whatever path-based `require atlas from "..."` form
    #      the consumer used. Works for monorepo siblings, vendored
    #      copies, or anywhere else Lake was told to look.
    #   2. `.lake/packages/atlas/bin` — the standard Lake-packages
    #      layout after a Git-style `require atlas from git "..."`.
    #   3. `./bin/atlas` — covers running from inside the atlas repo
    #      itself.
    # Missing directories are silently skipped so projects without
    # atlas don't pay for this.
    __atlas_dir=""
    if [ -r "$PWD/lake-manifest.json" ] && command -v jq >/dev/null 2>&1; then
      __atlas_dir_rel="$(jq -r '
        .packages[]?
        | select(.name == "atlas")
        | .dir // empty
      ' < "$PWD/lake-manifest.json" 2>/dev/null)"
      if [ -n "$__atlas_dir_rel" ]; then
        case "$__atlas_dir_rel" in
          /*) __atlas_dir="$__atlas_dir_rel" ;;
          *)  __atlas_dir="$PWD/$__atlas_dir_rel" ;;
        esac
      fi
    fi
    if [ -z "$__atlas_dir" ] && [ -d "$PWD/.lake/packages/atlas" ]; then
      __atlas_dir="$PWD/.lake/packages/atlas"
    fi
    if [ -z "$__atlas_dir" ] && [ -x "$PWD/bin/atlas" ]; then
      __atlas_dir="$PWD"
    fi
    if [ -n "$__atlas_dir" ] && [ -x "$__atlas_dir/bin/atlas" ]; then
      export PATH="$__atlas_dir/bin:$PATH"
    fi
    unset __atlas_dir __atlas_dir_rel

    # nixpkgs #409490: `lake build` fails with the default gcc linker
    # on NixOS. Switch to clang.
    export LEAN_CC=clang

    # Mathlib's `lake exe cache get` honors XDG_CACHE_HOME (falling back
    # to ~/.cache/mathlib). On systems where $HOME lives on a small
    # volume, point the cache at the msyw workspace root's `.cache/`
    # instead. Detection: walk up from $PWD until we find a directory
    # containing `shed/west.yml` (the msyw root marker). No-op outside
    # an msyw workspace.
    __msyw_root="$PWD"
    while [ "$__msyw_root" != "/" ] && [ ! -f "$__msyw_root/shed/west.yml" ]; do
      __msyw_root="$(dirname "$__msyw_root")"
    done
    if [ -f "$__msyw_root/shed/west.yml" ]; then
      export XDG_CACHE_HOME="$__msyw_root/.cache"
    fi
    unset __msyw_root
  '' + extraShellHook + ''

    # Prepend the REAL Lean lib/ to LIBRARY_PATH (after consumer hook).
    # The `${leanBin}` path is a thin stub whose `bin/` symlinks to the
    # underlying lean toolchain; the actual `lib/libc++.a` (with the
    # `__atomic_wait_native` / `__atomic_notify_one_native` symbols
    # libleanrt.a needs) lives at the symlink-target. Resolve via
    # readlink. Without this, `lake exe cache get` fails because the
    # linker picks up a nixpkgs libcxx missing those symbols.
    __real_lean_bin="$(readlink -f "${leanBin}/bin/lean" 2>/dev/null || true)"
    if [ -n "$__real_lean_bin" ]; then
      __real_lean_lib="$(dirname "$(dirname "$__real_lean_bin")")/lib"
      LIBRARY_PATH="$(echo "''${LIBRARY_PATH:-}" | tr ':' '\n' | grep -v "^$__real_lean_lib\$" | paste -sd: -)"
      export LIBRARY_PATH="$__real_lean_lib''${LIBRARY_PATH:+:$LIBRARY_PATH}"
    fi
    unset __real_lean_bin __real_lean_lib
  '';
}
