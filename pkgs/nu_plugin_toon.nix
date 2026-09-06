{
  stdenv,
  lib,
  rustPlatform,
  pkg-config,
  nix-update-script,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "nu_plugin_toon";
  version = "0.108.0";

  src = fetchFromGitHub {
    owner = "drew-council";
    repo = "nu_plugin_toon";
    rev = "9e8741ea7d08181de17b55ad58a336b6217efcb0";
    hash = "sha256-40mICAr615g3El0p+/8OPxplvjBKv9kGpu2HAo4WzFQ=";
  };

  cargoHash = "sha256-poCrn89D/w1xGOGj1tONzp0vzIJAg377prr33ecSskQ=";

  # nativeBuildInputs = [ pkg-config ] ++ lib.optionals stdenv.cc.isClang [ rustPlatform.bindgenHook ];

  # there are no tests
  doCheck = false;

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Nushell plugin for working with TOON format";
    mainProgram = "nu_plugin_toon";
    homepage = "https://github.com/drew-council/nu_plugin_toon";
    license = lib.licenses.mit;
  };
})
