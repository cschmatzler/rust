{
  description = "Christoph's shared Rust tooling and house style";

  inputs = {
    nixpkgs.url = "github:cachix/devenv-nixpkgs/rolling";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    devenv.url = "github:cachix/devenv/v2.4.0";
    # Keep the CLI's upstream package set to use its published binary cache.
    devenv.inputs.nixpkgs.url = "github:cachix/devenv-nixpkgs/256551e45f6303e142ab4a98be1bf243feb77dc0";
  };

  outputs =
    inputs@{ self, nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: import nixpkgs { inherit system; };
    in
    {
      devenvModules.default = import ./nix/module.nix { inherit inputs; };

      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          mr-boxington = pkgs.callPackage ./nix/mr-boxington.nix { };
          devenv = inputs.devenv.packages.${system}.devenv;
          default = self.packages.${system}.mr-boxington;
        }
      );

      formatter = forAllSystems (system: (pkgsFor system).nixfmt);

      checks = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          python = pkgs.python3.withPackages (ps: [ ps.tomlkit ]);
        in
        {
          configure =
            pkgs.runCommand "rust-style-configure-tests"
              {
                nativeBuildInputs = [ python ];
              }
              ''
                export PYTHONDONTWRITEBYTECODE=1
                python ${./tests/test_configure.py} ${./scripts/configure.py}
                touch "$out"
              '';
        }
      );

      templates.default = {
        path = ./template;
        description = "Import the shared Rust style into an existing Cargo project";
      };
    };
}
