{
  lib,
  stdenvNoCC,
  cacert,
  zola,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "blog";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  nativeBuildInputs = [
    cacert
    zola
  ];

  # zola builds a reqwest client while loading templates, which panics without
  # a CA bundle. The site itself is rendered offline; the certs are never used.
  SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    zola build --output-dir public
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r public/. "$out/"
    runHook postInstall
  '';

  meta = {
    description = "Rendered static site of the technical blog";
    platforms = lib.platforms.all;
  };
})
