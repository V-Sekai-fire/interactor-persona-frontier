# SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: Apache-2.0 OR MIT
{ lib, stdenv, fetchgit, leanToolchain, git, cacert, autoPatchelfHook }:

# Lake resolves its dependencies from git and checks each checkout's revision, so every dependency is
# fetched with its .git kept, at the revision in the planner's lake-manifest.json, and placed in
# .lake/packages before the offline build. To move to a newer planner, change `rev` and the hashes below.
let
  dep = name: url: rev: hash: {
    inherit name;
    src = fetchgit { inherit url rev hash; leaveDotGit = true; };
  };

  deps = [
    (dep "lean-yaml-ld" "https://github.com/V-Sekai-fire/lean-yaml-ld"
      "8a7d1c5a83c1935fa9751bb5e9a55585557136e1" "sha256-u3OXPI6XgBd4WK8B3n7wz51l2nUcrkUq4hvTZXEA/64=")
    (dep "persona" "https://github.com/V-Sekai-fire/interactor-taskweft-persona"
      "6f63c7e3c05133d0d0a4a3ad6a3e4d277a69b7bb" "sha256-muSvTJMMUtnbYLGjk8+6ynikCWABYCOEqFT0XxfgFdo=")
    (dep "plausible-witness-dag" "https://github.com/V-Sekai-fire/plausible-witness-dag"
      "f18818941e8914b110f85ec330889a4785c01bf1" "sha256-zzugPH1RI46tfxGWjP3JOZ8dD5wog9A7gtN8V/SvZ8M=")
    (dep "plausible" "https://github.com/leanprover-community/plausible"
      "118aa17ee84656b8bd727fef7c458ee8c833385c" "sha256-n/B8mI0FT3RImWD9PoQgJgKSFegYAnbU4x3wXhTud+8=")
    (dep "Plausible" "https://github.com/leanprover-community/plausible"
      "118aa17ee84656b8bd727fef7c458ee8c833385c" "sha256-n/B8mI0FT3RImWD9PoQgJgKSFegYAnbU4x3wXhTud+8=")
    (dep "entity_packet" "https://github.com/V-Sekai-fire/contract-entity-packet"
      "fe7a9627a9b23134f998a50cd854e9cc6743c536" "sha256-qWbtFQv+4EOIlutFkJ3+WSF99HHARq4IDCZb7Idjz+I=")
    (dep "LeanSlang" "https://github.com/V-Sekai-fire/contract-lean-slang"
      "01dbd396639f3ea44c87bef209a1449bd8d12844" "sha256-gyMUuA8aOAijXzNmM71yVyL41wQLpol6+ZFBd3SU4EE=")
  ];
in
stdenv.mkDerivation {
  pname = "frontier";
  version = "0";

  # the flake is part of the repository, so the planner is built from the checkout the flake came from
  src = lib.cleanSource ../.;

  # Lean links against the toolchain's own libc, so the binary names /lib64 as its loader, which NixOS lacks;
  # autoPatchelfHook points it at this package set's glibc.
  nativeBuildInputs = [ leanToolchain git cacert autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR
    git config --global --add safe.directory '*'
    mkdir -p .lake/packages
    ${lib.concatMapStrings (d: ''
      cp -r ${d.src} .lake/packages/${d.name}
      chmod -R u+w .lake/packages/${d.name}
    '') deps}
    lake build frontier frontier_witness frontier_store frontier_packets
    runHook postBuild
  '';

  # the witness is the unit gate, so a build that fails it does not exist; it runs after the loader is
  # patched, because the toolchain's binaries name a loader that NixOS lacks
  doInstallCheck = true;
  installCheckPhase = ''
    $out/libexec/frontier_witness
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 .lake/build/bin/frontier $out/bin/frontier
    install -Dm755 .lake/build/bin/frontier_witness $out/libexec/frontier_witness
    mkdir -p $out/share/frontier
    cp -r seeds $out/share/frontier/seeds
    runHook postInstall
  '';

  meta = {
    description = "The frontier planner";
    homepage = "https://github.com/V-Sekai-fire/interactor-persona-frontier";
    license = lib.licenses.mit;
    mainProgram = "frontier";
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
}
