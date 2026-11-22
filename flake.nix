{
  description = "The frontier planner for Nix";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f system);
      pkgsFor = system: import nixpkgs { inherit system; overlays = [ self.overlays.default ]; };
    in {
      overlays.default = import ./nix/overlay.nix;

      nixosModules.default = import ./nix/module.nix;

      packages = forAll (system:
        let pkgs = pkgsFor system; in {
          default = pkgs.frontier;
          frontier = pkgs.frontier;
        });

      checks.x86_64-linux.service = import ./nix/test.nix { pkgs = pkgsFor "x86_64-linux"; inherit self; };
    };
}
