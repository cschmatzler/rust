{
  description = "Christoph's shared Rust tooling and house style";

  inputs = {
    nixpkgs.url = "github:cachix/devenv-nixpkgs/rolling";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
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
