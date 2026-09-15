{
  pkgs,
  lib,
  config,
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

    nativeBuildInputs = [
      pkgs.makeWrapper
      pkgs.copyDesktopItems
    ];

    desktopItems = [
      (pkgs.makeDesktopItem {
        name = "cogfly";
        exec = "cogfly";
        icon = "cogfly";
        desktopName = "Cogfly";
        genericName = "Silksong Mod Manager";
        categories = [
          "Game"
          "PackageManager"
        ];
      })
    ];

    installPhase = ''
      runHook preInstall

      install -Dm444 "$src" "$out/share/cogfly/cogfly.jar"
      makeWrapper "${pkgs.jdk25}/bin/java" "$out/bin/cogfly" \
        --add-flags "-jar $out/share/cogfly/cogfly.jar" \
        --prefix PATH : "${lib.makeBinPath [ pkgs.zenity ]}"

      # icon lives inside the jar at assets/icon.png
      mkdir icon
      (cd icon && ${pkgs.jdk25}/bin/jar -xf "$src" assets/icon.png)
      install -Dm644 icon/assets/icon.png \
        "$out/share/icons/hicolor/128x128/apps/cogfly.png"

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
  # On NixOS the game only finds its X11 libraries inside an FHS environment,
  # so Cogfly's launch script must re-exec through steam-run. Cogfly copies
  # run_bepinex.sh from its doorstop cache into the game folder, and replaces
  # both when it updates its BepInEx pack.
  patchDoorstop = pkgs.writeShellScriptBin "cogfly-patch-doorstop" ''
    patch() {
      local f="$1" tmp
      [ -f "$f" ] || return 0
      grep -q COGFLY_NIXOS_WRAPPER "$f" && return 0
      tmp="$(mktemp)"
      {
        head -n 1 "$f"
        cat ${pkgs.writeText "cogfly-doorstop-wrapper" ''
          # COGFLY_NIXOS_WRAPPER: outside Steam's container the game needs steam-run
          # (FHS env) to find its X11 libraries; inside the container this is skipped.
          if [ -z "$COGFLY_NIXOS_WRAPPER" ] && [ ! -d /run/pressure-vessel ] \
              && command -v steam-run >/dev/null 2>&1; then
          	COGFLY_NIXOS_WRAPPER=1 exec steam-run /bin/sh "$0" "$@"
          fi
        ''}
        tail -n +2 "$f"
      } > "$tmp"
      chmod --reference="$f" "$tmp"
      mv "$tmp" "$f"
      echo "patched $f"
    }

    patch "$HOME/.local/share/Cogfly/doorstop/run_bepinex.sh"
    patch "/mnt/storage/SteamLibrary/steamapps/common/Hollow Knight Silksong/run_bepinex.sh"
  '';
in
{
  environment.systemPackages = [
    pkgs.archipelago
    pkgs.zenity # cogfly file/folder pickers
    cogfly
  ];

  # Cogfly: re-patch its doorstop scripts on every home-manager activation
  # (idempotent, no-op when already patched or Cogfly isn't installed yet).
  # Needed because Cogfly replaces run_bepinex.sh whenever it updates its
  # BepInEx pack, and those files live outside the nix store.
  # Archipelago: loads .apworld files from ~/.local/share/Archipelago/worlds
  # when its install directory is read-only (as it is from the nix store).
  home-manager.users.${vars.user} = {
    home.activation.cogflyDoorstopPatch =
      config.home-manager.users.${vars.user}.lib.dag.entryAfter [ "writeBoundary" ]
        ''
          run "${lib.getExe patchDoorstop}"
        '';

    home.file.".local/share/Archipelago/worlds/silksong.apworld".source =
      "${silksong-apworld}/share/archipelago/worlds/silksong.apworld";
  };
}
