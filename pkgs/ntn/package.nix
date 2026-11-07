# Notion CLI (`ntn`) - Notion's official CLI for authentication, Workers, and API requests.
# Distributed as an npm tarball that bundles Bun-compiled standalone binaries per platform.
{
  fetchurl,
  lib,
  stdenv,
}:

stdenv.mkDerivation {
  pname = "ntn";
  version = "0.23.3";

  src = fetchurl {
    url = "https://registry.npmjs.org/ntn/-/ntn-0.23.3.tgz";
    hash = "sha256-Zb2VahunoGk8P1VwNq6P9EfOLYrkg5plvaE3wXwoWM4=";
  };

  # Bun compile stores the JavaScript payload in a custom binary section.
  # Stripping or patching removes it and makes the binary fail at startup.
  dontStrip = true;
  dontPatchELF = true;

  meta = {
    description = "Notion CLI";
    homepage = "https://developers.notion.com/cli";
    license = lib.licenses.mit;
    mainProgram = "ntn";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
      "x86_64-darwin"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };

  installPhase = ''
    runHook preInstall

    system_dir=${
      {
        x86_64-linux = "ntn-linux-x64";
        aarch64-linux = "ntn-linux-arm64";
        x86_64-darwin = "ntn-darwin-x64";
        aarch64-darwin = "ntn-darwin-arm64";
      }
      .${stdenv.hostPlatform.system} or (throw "ntn is not supported on ${stdenv.hostPlatform.system}")
    }

    install -Dm755 dist/$system_dir/ntn -t $out/bin
    install -Dm644 LICENSE.md -t $out/share/licenses/ntn
    install -Dm644 README.md -t $out/share/doc/ntn

    runHook postInstall
  '';
}
