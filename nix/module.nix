{ inputs }:
{ lib, pkgs, ... }:

let
  rust =
    (inputs.rust-overlay.lib.mkRustBin { } pkgs).fromRustupToolchainFile
      ../config/rust-toolchain.toml;
  mbx = pkgs.callPackage ./mr-boxington.nix { };
  cargo = pkgs.writeShellScriptBin "cargo" ''
    export CARGO=${rust}/bin/cargo
    export MBX_CARGO_SHIM_MODE=1
    export MBX_CARGO_SHIM_PATH="$0"
    exec ${mbx}/bin/mbx "$@"
  '';
  lintFlags = lib.concatMapStringsSep " " (lint: "--warn=${lint}") (import ../config/lints.nix);
in
{
  languages.rust = {
    enable = true;
    # mbx 1.21 skips library caching with an explicit linker.
    clangLinker.enable = false;
    toolchainPackage = rust;
    toolchain = lib.genAttrs [ "cargo" "rustc" "clippy" "rustfmt" "rust-analyzer" "rust-src" ] (
      _: rust
    );
    lsp.package = rust;
  };

  packages = [
    (lib.hiPrio cargo)
    mbx
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

  scripts = {
    fmt.exec = ''cargo fmt --all "$@"'';
    lint.exec = ''cargo clippy --workspace --all-targets "$@" -- -D warnings ${lintFlags}'';
    rust-test.exec = ''
      cargo nextest run --workspace --tool-config-file cschmatzler:${../config/nextest.toml} "$@" &&
      cargo test --workspace --doc
    '';
    check.exec = "cargo fmt --all -- --check && lint && rust-test";
  };

  enterTest = "check";
}
