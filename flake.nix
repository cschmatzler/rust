{
  description = "Christoph's shared Rust tooling and house style";

  inputs = {
    nixpkgs.url = "github:cachix/devenv-nixpkgs/rolling";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    fenix.url = "github:nix-community/fenix";
    fenix.inputs.nixpkgs.follows = "nixpkgs";
    mr-boxington.url = "github:jdx/mr-boxington";
    mr-boxington.inputs.nixpkgs.follows = "nixpkgs";
    blaze.url = "github:indexable-inc/blaze";
    blaze.inputs.nixpkgs.follows = "nixpkgs";
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
          blazeSource = pkgs.applyPatches {
            name = "blaze-nix-source";
            src = inputs.blaze;
            patches = [ ./nix/blaze-glibc.patch ];
          };
          blaze = (import "${blazeSource}/flake.nix").outputs (
            inputs.blaze.inputs
            // {
              self = inputs.blaze // {
                outPath = blazeSource;
              };
            }
          );
        in
        {
          blaze = blaze.packages.${system}.blaze;
          mr-boxington = inputs.mr-boxington.packages.${system}.mbx;
          default = self.packages.${system}.mr-boxington;
        }
      );

      formatter = forAllSystems (system: (pkgsFor system).nixfmt);

      templates.default = {
        path = ./template;
        description = "Import the shared Rust style into an existing Cargo project";
      };
    };
}
