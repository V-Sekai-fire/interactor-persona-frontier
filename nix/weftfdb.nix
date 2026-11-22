{ stdenv, fetchgit, cmake, foundationdb, sqlite }:

# The store's FoundationDB virtual file system, as the loadable module the planner opens its database through.
stdenv.mkDerivation {
  pname = "weftfdb";
  version = "0";

  src = fetchgit {
    url = "https://github.com/V-Sekai-fire/datasource-store";
    rev = "abb688b70be3dc160c2cf5f32ff7d8e05da799ba";
    hash = "sha256-O2sD+WDr4r2uTGyyujBNeAb9d2gpde9z9u7tnswJy14=";
  };

  nativeBuildInputs = [ cmake ];
  buildInputs = [ foundationdb sqlite ];
  cmakeBuildType = "Release";
  buildFlags = [ "weftfdb" ];

  installPhase = ''
    install -Dm755 weftfdb.so $out/lib/weftfdb.so
  '';
}
