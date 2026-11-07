{
  pkgs,
  lib,
  config,
  ...
}:
let
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
    pkgs.cogfly
  ];

  # Cogfly: re-patch its doorstop scripts on every home-manager activation
  # (idempotent, no-op when already patched or Cogfly isn't installed yet).
  # Needed because Cogfly replaces run_bepinex.sh whenever it updates its
  # BepInEx pack, and those files live outside the nix store.
  # Archipelago: loads .apworld files from ~/.local/share/Archipelago/worlds
  # when its install directory is read-only (as it is from the nix store).
  home-manager.users.${config.my.user.name} = {
    home.activation.cogflyDoorstopPatch =
      config.home-manager.users.${config.my.user.name}.lib.dag.entryAfter [ "writeBoundary" ]
        ''
          run "${lib.getExe patchDoorstop}"
        '';

    home.file.".local/share/Archipelago/worlds/silksong.apworld".source =
      "${silksong-apworld}/share/archipelago/worlds/silksong.apworld";
  };
}
