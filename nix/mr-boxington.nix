{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "1.21.0";
  releases = {
    x86_64-linux = {
      target = "x86_64-unknown-linux-musl";
      hash = "sha256-UiWjt3+Q4c09HvDRBUzNRZOuGbLJi4Fa8bgqTf7Q+Xs=";
    };
    aarch64-linux = {
      target = "aarch64-unknown-linux-musl";
      hash = "sha256-EH+GlV+DI+qWypDKLQbUm5sbmXid2AB/cfnFm7F7ttc=";
    };
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-SqnaEI6QxsJpgZ/tjoIqQvUQEmCWHNURmZ+s1XJs+dk=";
    };
  };
  release = releases.${stdenvNoCC.hostPlatform.system};
in
stdenvNoCC.mkDerivation {
  pname = "mr-boxington";
  inherit version;

  src = fetchurl {
    url = "https://github.com/jdx/mr-boxington/releases/download/v${version}/mbx-${release.target}.tar.gz";
    inherit (release) hash;
  };

  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 mbx "$out/bin/mbx"
    runHook postInstall
  '';

  meta = {
    description = "Shared compiler cache for Cargo builds";
    homepage = "https://mr-boxington.jdx.dev";
    license = lib.licenses.mit;
    platforms = builtins.attrNames releases;
    mainProgram = "mbx";
  };
}
