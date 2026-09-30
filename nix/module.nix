{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
{
  languages.rust = {
    enable = true;
    # mbx 1.21 skips library caching with an explicit linker.
    clangLinker.enable = false;
    toolchainPackage =
      (inputs.rust-overlay.lib.mkRustBin { } pkgs).fromRustupToolchainFile
        ../config/rust-toolchain.toml;
    toolchain = lib.genAttrs [ "cargo" "rustc" "clippy" "rustfmt" "rust-analyzer" "rust-src" ] (
      _: config.languages.rust.toolchainPackage
    );
    lsp.package = config.languages.rust.toolchainPackage;
  };

  packages = [
    (lib.hiPrio (
      pkgs.writeShellScriptBin "cargo" ''
        export CARGO=${config.languages.rust.toolchainPackage}/bin/cargo
        export MBX_CARGO_SHIM_MODE=1
        export MBX_CARGO_SHIM_PATH="$0"
        exec ${pkgs.callPackage ./mr-boxington.nix { }}/bin/mbx "$@"
      ''
    ))
    (pkgs.callPackage ./mr-boxington.nix { })
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
    lint.exec = ''
      cargo clippy --workspace --all-targets "$@" -- -D warnings ${lib.escapeShellArgs (import ../config/lints.nix)}
    '';
    rust-test.exec = ''
      cargo nextest run --workspace --tool-config-file cschmatzler:${../config/nextest.toml} "$@" &&
      cargo test --workspace --doc
    '';
    check.exec = "cargo fmt --all -- --check && lint && rust-test";
  };

  enterTest = "check";
}
