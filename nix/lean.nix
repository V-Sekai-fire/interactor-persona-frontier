# SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: Apache-2.0 OR MIT
{ stdenv, fetchurl, zstd, autoPatchelfHook, zlib }:

# The Lean toolchain the planner's lean-toolchain file names, from the official release, because the
# dependencies are written against that version and nixpkgs carries a different one.
let
  version = "4.34.1";
  release = {
    x86_64-linux = {
      file = "lean-${version}-linux.tar.zst";
      hash = "sha256-R79LvXj3DC6WcFmKtxJNkrbvtzMP8z5fu0Aw9v1y5OQ=";
    };
    aarch64-linux = {
      file = "lean-${version}-linux_aarch64.tar.zst";
      hash = "sha256-/bl0ws20Yn4JDV1AB7kT4J0TxIaHIPtVlOIoCLPenjc=";
    };
  }.${stdenv.hostPlatform.system};
in
stdenv.mkDerivation {
  pname = "lean-toolchain";
  inherit version;

  src = fetchurl {
    url = "https://github.com/leanprover/lean4/releases/download/v${version}/${release.file}";
    inherit (release) hash;
  };

  nativeBuildInputs = [ zstd autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib zlib ];

  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p $out
    cp -r lean-*/. $out/
  '';
}
