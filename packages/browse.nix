{
  lib,
  stdenv,
  fetchurl,
  glibc,
  patchelf,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "browse";
  version = "0.1.5";

  src = fetchurl {
    url = "https://registry.npmjs.org/@opencode/browse-linux-x64/-/browse-linux-x64-${finalAttrs.version}.tgz";
    hash = "sha512-4C5eUD1WkeozFRTsnSWRCzeMHbVs3FOp2QEI5+/yqJSFy00Sc+E7YvC01lSnEEmdWy85AMUCsrqqwNAFJTGa1A==";
  };

  dontUnpack = true;
  dontBuild = true;
  dontFixup = true;

  nativeBuildInputs = [ patchelf ];

  installPhase = ''
    runHook preInstall
    tar -xzf $src
    install -Dm755 package/bin/browse $out/bin/browse
    patchelf --set-interpreter ${glibc}/lib64/ld-linux-x86-64.so.2 $out/bin/browse
    runHook postInstall
  '';

  meta = {
    description = "MCP server and CLI that let agents use your real browser";
    homepage = "https://github.com/anomalyco/browse";
    license = lib.licenses.mit;
    mainProgram = "browse";
    platforms = [ "x86_64-linux" ];
  };
})
