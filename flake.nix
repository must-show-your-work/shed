{
  description = "must-show-your-work — workspace flake (west + multi-repo tooling)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    # lean4-nix: Lean toolchain via Nix (replaces elan-with-FHS on NixOS).
    # Exposed downstream through `flake.lib.mkLeanShell` so per-repo
    # flakes (atlas, geometry-is-your-friend, every-waking-moment) consume
    # one shared wiring instead of each redeclaring it.
    lean4-nix = {
      url = "github:lenianiva/lean4-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Garnix binary cache: lean4-nix's CI publishes derivations here.
  # First `nix develop` on a consumer prompts for --accept-flake-config.
  nixConfig = {
    extra-substituters = [ "https://cache.garnix.io" ];
    extra-trusted-public-keys = [ "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g=" ];
  };

  outputs = { self, nixpkgs, flake-parts, lean4-nix, ... } @ inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-darwin" "aarch64-linux" ];

      # Workspace-level lib. `mkLeanShell` is the shared Lean-shell
      # factory; consumer flakes pass their own `manifest` (per-repo
      # `lean-toolchain` pin → tag + url + hash) plus optional extras.
      flake.lib.mkLeanShell = args:
        import ./lib/lean-shell.nix (args // {
          inherit nixpkgs lean4-nix;
        });

      perSystem = { config, pkgs, system, ... }: let
        # Runtime libs that `uv`-installed wheels with native code need at
        # import time (dlopen). `pymupdf` and similar Python tools ship
        # C++ extensions linked against libstdc++; on NixOS the system
        # loader can't find it without an explicit `LD_LIBRARY_PATH`.
        # `resvg` here for lean.nvim's `lua/tui/svg.lua` FFI dlopen of
        # `libresvg.so` — without it the InfoView text-serializes SVGs
        # from atlas figures instead of rasterizing into kitty graphics.
        runtimeLibs = [ pkgs.stdenv.cc.cc.lib pkgs.resvg ];
      in {
        devShells.default = pkgs.mkShell {
          name = "msyw workspace";
          packages = with pkgs; [
            python3Packages.west
            git
            just
            # `uv` is here so `uvx lean-lsp-mcp` (configured in .mcp.json) can
            # JIT-install + run the Lean LSP MCP server from PyPI. Other MCP
            # servers that ship as Python packages can use the same pattern.
            uv
            # GitHub MCP server (official, Go binary). Driven from .mcp.json
            # in --read-only mode; auth via $GH_TOKEN from .env.
            github-mcp-server
            # `npx` for npm-packaged MCP servers (context7).
            nodejs
            # `resvg` CLI — peer of the LD_LIBRARY_PATH entry above. Some
            # lean.nvim paths shell out to the binary instead of dlopen'ing
            # libresvg, so we need both.
            resvg
            # `sqlite` CLI — `atlas serve`'s annotation store is a
            # SQLite DB at `<project>/blueprint/atlas.sqlite`; having
            # the bare command around makes ad-hoc inspection and
            # cleanup queries trivial.
            sqlite
          ];

          shellHook = ''
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath runtimeLibs}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

            # Atlas tooling — same detection as `lib/lean-shell.nix`. Lifted
            # here so `nix develop ../shed` from inside an atlas checkout
            # (or any project depending on atlas via Lake) puts `atlas`
            # on PATH without needing the consumer's own flake. Three
            # resolution strategies in order of accuracy:
            #   1. `lake-manifest.json` — `.packages[].dir` for atlas.
            #   2. `.lake/packages/atlas/bin` — Git-style Lake layout.
            #   3. `./bin/atlas` — running from inside the atlas repo.
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
          '';
        };
      };
    };
}
