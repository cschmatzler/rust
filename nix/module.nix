{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  mr-boxington = inputs.mr-boxington.packages.${pkgs.stdenv.hostPlatform.system}.mbx;
in
{
  languages.rust = {
    enable = true;
    # mbx 1.21 skips library caching with an explicit linker.
    clangLinker.enable = false;
    # Fenix can use newly released toolchains before rust-overlay indexes them.
    toolchainPackage = inputs.fenix.packages.${pkgs.stdenv.hostPlatform.system}.fromToolchainFile {
      file = ../config/rust-toolchain.toml;
      sha256 = "ce6dddc886364f8d786514771212cebe9b731ba82d6b859951c6b0ccc516b6a2";
    };

    toolchain =
      lib.genAttrs [ "cargo" "rustc" "clippy" "rust-analyzer" "rust-src" ] (
        _: config.languages.rust.toolchainPackage
      )
      // {
        # Import grouping requires nightly rustfmt; compilation stays stable.
        rustfmt = (inputs.rust-overlay.lib.mkRustBin { } pkgs).nightly."2026-09-30".rustfmt;
      };
    lsp.package = config.languages.rust.toolchainPackage;
  };

  env.MBX_TARGET_KEEP = config.devenv.root;
  env.RUSTFMT = "${config.languages.rust.toolchain.rustfmt}/bin/rustfmt";

  packages = [
    (lib.hiPrio config.languages.rust.toolchain.rustfmt)
    (lib.hiPrio (
      pkgs.writeShellScriptBin "cargo" ''
        export CARGO=${config.languages.rust.toolchainPackage}/bin/cargo
        export MBX_CARGO_SHIM_MODE=1
        export MBX_CARGO_SHIM_PATH="$0"
        exec ${mr-boxington}/bin/mbx "$@"
      ''
    ))
    mr-boxington
    pkgs.cargo-nextest
  ];

  files."rustfmt.toml" = {
    source = ../config/rustfmt.toml;
    copyMode = "copy";
  };
  files."clippy.toml" = {
    source = ../config/clippy.toml;
    # A store symlink prevents mbx from caching Clippy results.
    copyMode = "copy";
  };

}
