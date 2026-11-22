final: prev: {
  frontier-lean-toolchain = final.callPackage ./lean.nix { };
  frontier-weftfdb = final.callPackage ./weftfdb.nix { };
  frontier = final.callPackage ./frontier.nix { leanToolchain = final.frontier-lean-toolchain; };
}
