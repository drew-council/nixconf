{
  pkgs,
  lib,
  vars,
  ...
}:
let
  # Cogfly, a Silksong mod manager (Java jar release; needs Java 23+, zenity
  # for Linux file pickers).
  cogfly = pkgs.stdenvNoCC.mkDerivation {
    pname = "cogfly";
    version = "1.2.5";

    src = pkgs.fetchurl {
      url = "https://github.com/Nix-main/Cogfly/releases/download/1.2.5/Cogfly-1.2.5.jar";
      hash = "sha256-v0tfCmxezYe68n/gzbjYateRSGoNvAjBStAPZ6AUeHc=";
    };

    dontUnpack = true;

    nativeBuildInputs = [ pkgs.makeWrapper ];

    installPhase = ''
      runHook preInstall

      install -Dm444 "$src" "$out/share/cogfly/cogfly.jar"
      makeWrapper "${pkgs.jdk25}/bin/java" "$out/bin/cogfly" \
        --add-flags "-jar $out/share/cogfly/cogfly.jar" \
        --prefix PATH : "${lib.makeBinPath [ pkgs.zenity ]}"

      runHook postInstall
    '';

    meta = {
      description = "Cross-platform mod manager for Hollow Knight: Silksong";
      homepage = "https://github.com/Nix-main/Cogfly";
      license = lib.licenses.mit;
      mainProgram = "cogfly";
      platforms = lib.platforms.unix;
    };
  };

  # Silksong Archipelago randomizer .apworld.
  silksong-apworld = pkgs.stdenvNoCC.mkDerivation {
    pname = "silksong-apworld";
    version = "0.4.5-hotfix2";

    src = pkgs.fetchurl {
      url = "https://github.com/Batatvideogames/silksong-archipelago-randomizer/releases/download/v0.4.5-Hotfix2/silksong.apworld";
      hash = "sha256-XTsfq81Ceiug4gK+matoL+KwDYS4UwOibzcr26L6Ho8=";
    };

    dontUnpack = true;

    installPhase = ''
      runHook preInstall

      install -Dm444 "$src" "$out/share/archipelago/worlds/silksong.apworld"

      runHook postInstall
    '';

    meta = {
      description = "Archipelago .apworld for the Hollow Knight: Silksong randomizer";
      homepage = "https://github.com/Batatvideogames/silksong-archipelago-randomizer";
      license = lib.licenses.mit;
      platforms = lib.platforms.unix;
    };
  };
in
{
  environment.systemPackages = [
    pkgs.archipelago
    pkgs.zenity # cogfly file/folder pickers
    cogfly
  ];

  # Archipelago loads .apworld files from ~/.local/share/Archipelago/worlds
  # when its install directory is read-only (as it is from the nix store).
  home-manager.users.${vars.user}.home.file.".local/share/Archipelago/worlds/silksong.apworld".source =
    "${silksong-apworld}/share/archipelago/worlds/silksong.apworld";
}
