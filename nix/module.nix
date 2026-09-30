{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  root = config.devenv.root;
  overridePath = root + "/.config/rust-style.toml";
  overrides =
    if builtins.pathExists overridePath then
      builtins.fromTOML (builtins.readFile overridePath)
    else
      { };
  read = path: builtins.fromTOML (builtins.readFile path);
  lintDefaults = read ../config/lints.toml;
  lintOverrides = overrides.lints or { };
  lintGroups = lib.unique (builtins.attrNames lintDefaults ++ builtins.attrNames lintOverrides);
  lints = lib.genAttrs lintGroups (
    group: (lintDefaults.${group} or { }) // (lintOverrides.${group} or { })
  );
  lintFile = (pkgs.formats.toml { }).generate "rust-style-lints.toml" lints;
  python = pkgs.python3.withPackages (ps: [ ps.tomlkit ]);
  configure = "${python}/bin/python ${../scripts/configure.py} --root ${lib.escapeShellArg root} --lints ${lintFile}";
  rustBin = inputs.rust-overlay.lib.mkRustBin { } pkgs;
  projectToolchain = root + "/rust-toolchain.toml";
  sharedToolchain = (read ../config/rust-toolchain.toml).toolchain;
  selectedToolchain =
    if builtins.pathExists projectToolchain then (read projectToolchain).toolchain else sharedToolchain;
  toolchain = rustBin.fromRustupToolchain (
    selectedToolchain
    // {
      components = lib.unique (sharedToolchain.components ++ (selectedToolchain.components or [ ]));
    }
  );
  mbx = pkgs.callPackage ./mr-boxington.nix { };
  cargoShim = pkgs.writeShellScriptBin "cargo" ''
    export CARGO=${toolchain}/bin/cargo
    export MBX_CARGO_SHIM_MODE=1
    export MBX_CARGO_SHIM_PATH="$0"
    exec ${mbx}/bin/mbx "$@"
  '';
  cargoConfig = overrides.cargo or { };
  cargoArgs = lib.escapeShellArgs (
    [ "--workspace" ]
    ++ lib.optional (builtins.pathExists (root + "/Cargo.lock")) "--locked"
    ++ lib.optional (cargoConfig.all-features or false) "--all-features"
    ++ lib.optional (cargoConfig.no-default-features or false) "--no-default-features"
    ++ lib.optionals ((cargoConfig.features or [ ]) != [ ]) [
      "--features"
      (lib.concatStringsSep "," cargoConfig.features)
    ]
  );
in
{
  assertions = [
    {
      assertion = lib.all (
        key:
        builtins.elem key [
          "rustfmt"
          "clippy"
          "lints"
          "cargo"
        ]
      ) (builtins.attrNames overrides);
      message = "rust-style: supported override tables are rustfmt, clippy, lints, and cargo.";
    }
    {
      assertion = !(cargoConfig.all-features or false) || (cargoConfig.features or [ ]) == [ ];
      message = "rust-style: choose cargo.all-features or cargo.features, rather than both.";
    }
  ];

  languages.rust = {
    enable = true;
    # mbx 1.21 refuses an explicit -C linker even for library compilations.
    # Keep Cargo's native linker selection so those libraries remain cacheable.
    clangLinker.enable = false;
    toolchainPackage = toolchain;
    toolchain = lib.genAttrs [ "cargo" "rustc" "clippy" "rustfmt" "rust-analyzer" "rust-src" ] (
      _: toolchain
    );
    lsp.package = toolchain;
  };

  packages = [
    (lib.hiPrio cargoShim)
    mbx
    pkgs.cargo-nextest
    pkgs.cargo-llvm-cov
    pkgs.pkg-config
    pkgs.openssl
  ];

  files."rustfmt.toml" = {
    toml = (read ../config/rustfmt.toml) // (overrides.rustfmt or { });
    copyMode = "copy";
  };
  files."clippy.toml" = {
    toml = (read ../config/clippy.toml) // (overrides.clippy or { });
    # A store symlink escapes mbx's workspace mapping and prevents Clippy caching.
    copyMode = "copy";
  };

  tasks."rust-style:configure" = {
    cwd = root;
    before = [ "devenv:enterShell" ];
    status = "${configure} --check";
    exec = configure;
  };

  scripts = {
    lint.exec = ''
      cd ${lib.escapeShellArg root}
      exec cargo clippy ${cargoArgs} --all-targets "$@" -- -D warnings
    '';
    fmt.exec = ''
      cd ${lib.escapeShellArg root}
      exec cargo fmt --all "$@"
    '';
    rust-test.exec = ''
      set -euo pipefail
      cd ${lib.escapeShellArg root}
      profile=default
      if [ -n "''${CI:-}" ]; then profile=ci; fi
      cargo nextest run ${cargoArgs} --profile "$profile" \
        --tool-config-file cschmatzler:${../config/nextest.toml} "$@"
      cargo test ${cargoArgs} --doc
    '';
    check.exec = ''
      set -euo pipefail
      cd ${lib.escapeShellArg root}
      cargo fmt --all -- --check
      lint
      rust-test
    '';
  };

  enterTest = "check";
}
