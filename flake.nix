# SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: Apache-2.0 OR MIT
{
  description = "The frontier planner for Nix: a NixOS module, and the same service on Ubuntu through system-manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    system-manager = {
      url = "github:numtide/system-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, system-manager }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f system);
      # the Go pseudo-version of this commit: UTC commit time and the first 12 hex digits of its hash
      revision = self.rev or self.dirtyRev or "000000000000";
      version = "0.0.0-${builtins.substring 0 14 self.lastModifiedDate}-${builtins.substring 0 12 revision}";
      overlay = import ./nix/overlay.nix { inherit version; };
      pkgsFor = system: import nixpkgs { inherit system; overlays = [ overlay ]; };
      # Ubuntu: `nix run github:numtide/system-manager -- switch --flake .#default` (SQLite) or `.#foundationdb`; system-manager
      # mocks the firewall and has users, so the NixOS module and nixpkgs' FoundationDB and osquery modules load unchanged
      ubuntu = system: store: system-manager.lib.makeSystemConfig {
        modules = [
          ./nix/module.nix
          ({ nixosModulesPath, ... }: {
            imports = [
              (nixosModulesPath + "/services/databases/foundationdb.nix")
              (nixosModulesPath + "/services/monitoring/osquery.nix")
            ];
          })
          {
            nixpkgs.hostPlatform = system;
            services.frontier = {
              enable = true;
              package = self.packages.${system}.frontier;
              weftfdb = self.packages.${system}.weftfdb;
            } // store;
          }
        ];
      };
    in {
      overlays.default = overlay;

      nixosModules.default = import ./nix/module.nix;

      systemManagerModules.default = import ./nix/module.nix;

      systemConfigs = {
        default = ubuntu "x86_64-linux" { };
        foundationdb = ubuntu "x86_64-linux" { foundationdb = true; };
      };

      packages = forAll (system:
        let pkgs = pkgsFor system; in {
          default = pkgs.frontier;
          frontier = pkgs.frontier;
          weftfdb = pkgs.frontier-weftfdb;
        });

      checks.x86_64-linux = let pkgs = pkgsFor "x86_64-linux"; in {
        service = import ./nix/test.nix { inherit pkgs self; };
        ubuntu-sqlite = import ./nix/test-ubuntu.nix { inherit pkgs system-manager; toplevel = self.systemConfigs.default; foundationdb = false; };
        ubuntu-foundationdb = import ./nix/test-ubuntu.nix { inherit pkgs system-manager; toplevel = self.systemConfigs.foundationdb; foundationdb = true; };
      };
    };
}
