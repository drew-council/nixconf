{
  buildFHSEnv,
  fetchurl,
  lib,
  stdenv,
}:

let
  version = "2.0.0";
  system = stdenv.hostPlatform.system;
  artifact =
    {
      x86_64-linux = {
        name = "linear-x86_64-unknown-linux-gnu.tar.xz";
        hash = "sha256-r/tZRnLC8iDO9o+nz+uBOUXEAQeJpLjMLA5GRo/reHA=";
      };
      aarch64-linux = {
        name = "linear-aarch64-unknown-linux-gnu.tar.xz";
        hash = "sha256-bDr90Rx8D7kAU9S1OyclK1w1u3XGeTgyNL7yCiVVjqw=";
      };
      aarch64-darwin = {
        name = "linear-aarch64-apple-darwin.tar.xz";
        hash = "sha256-Eh/h7ubZCyLnbk6Yy7YkR07s2XCkpMYi/U1QiJtX2sw=";
      };
    }
    .${system} or (throw "linear-cli is not supported on ${system}");
  src = fetchurl {
    url = "https://github.com/schpet/linear-cli/releases/download/v${version}/${artifact.name}";
    inherit (artifact) hash;
  };
  meta = {
    description = "CLI tool for Linear issue tracker";
    homepage = "https://github.com/schpet/linear-cli";
    license = lib.licenses.mit;
    mainProgram = "linear";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };

  raw = stdenv.mkDerivation {
    pname = "linear-cli-unwrapped";
    inherit version src;

    # `deno compile` stores the JavaScript payload in a custom binary section.
    # Stripping or patching removes it and makes the binary fail at startup.
    dontStrip = true;
    dontPatchELF = true;

    installPhase = ''
      runHook preInstall

      install -Dm755 linear -t $out/bin
      install -Dm644 LICENSE -t $out/share/licenses/linear-cli
      install -Dm644 README.md CHANGELOG.md -t $out/share/doc/linear-cli

      runHook postInstall
    '';
  };
in
if stdenv.hostPlatform.isLinux then
  buildFHSEnv {
    name = "linear";
    pname = "linear-cli";
    inherit version meta;

    targetPkgs = pkgs: [ pkgs.gcc.cc.lib ];
    runScript = "${raw}/bin/linear";

    extraInstallCommands = ''
      ln -s $out/bin/linear-cli $out/bin/linear
      mkdir -p $out/share
      ln -s ${raw}/share/doc $out/share/doc
      ln -s ${raw}/share/licenses $out/share/licenses
    '';
  }
else
  raw.overrideAttrs {
    pname = "linear-cli";
    inherit meta;
  }
