# Workspace-wide Lean toolchain pin. Consumed by `lib/lean-shell.nix` as
# the default; per-project flakes can override by passing `manifest = …`
# explicitly to `mkLeanShell`.
#
# Bump procedure when moving the pin:
#   for arch in linux linux_aarch64 darwin darwin_aarch64; do
#     nix store prefetch-file --hash-type sha256 \
#       "https://github.com/leanprover/lean4/releases/download/<tag>/lean-<ver>-${arch}.tar.zst"
#   done
# Update tag + the four hashes below in lockstep. Also update each
# consumer project's `./lean-toolchain` to match.
{
  tag = "v4.31.0";
  toolchain = {
    x86_64-linux = {
      url  = "https://github.com/leanprover/lean4/releases/download/v4.31.0/lean-4.31.0-linux.tar.zst";
      hash = "sha256-B6YzzI2RUcvAiCXqTN2lDUsCosnLhSwBMbEwRvScrX8=";
    };
    aarch64-linux = {
      url  = "https://github.com/leanprover/lean4/releases/download/v4.31.0/lean-4.31.0-linux_aarch64.tar.zst";
      hash = "sha256-sb8dPFhrds9KhiEqWV2Lnt2Z9DikHM6F1XgPqTR8gRs=";
    };
    x86_64-darwin = {
      url  = "https://github.com/leanprover/lean4/releases/download/v4.31.0/lean-4.31.0-darwin.tar.zst";
      hash = "sha256-bax6j51tC8M5tOqTdsBqiPP9Gn9GK+s8fe2fvJNPP7U=";
    };
    aarch64-darwin = {
      url  = "https://github.com/leanprover/lean4/releases/download/v4.31.0/lean-4.31.0-darwin_aarch64.tar.zst";
      hash = "sha256-JkEFUAyKvfN7aP/gM5Cng+0lmAeAciJpjajdktbOCic=";
    };
  };
}
