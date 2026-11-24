# SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: Apache-2.0 OR MIT
final: prev: {
  frontier-lean-toolchain = final.callPackage ./lean.nix { };
  frontier-weftfdb = final.callPackage ./weftfdb.nix { };
  frontier = final.callPackage ./frontier.nix { leanToolchain = final.frontier-lean-toolchain; };
}
