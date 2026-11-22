final: prev: {
  frontier-lean-toolchain = final.callPackage ./lean.nix { };
  frontier = final.callPackage ./frontier.nix { leanToolchain = final.frontier-lean-toolchain; };
}
