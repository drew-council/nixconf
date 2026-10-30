{
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  cfg = osConfig.gameMode;
  monitorConfig = import ../monitor-config.nix;
  hostMonitorConfig = monitorConfig.hosts.${osConfig.networking.hostName};
  audioProfile = hostMonitorConfig.profiles.${hostMonitorConfig.gameModeProfile};
  switchaudio = import ../../switchaudio/package.nix { inherit pkgs; };

  configJson = pkgs.writeText "game-mode.json" (
    builtins.toJSON {
      inherit (cfg) connector;
      audio = {
        alsaName = audioProfile.defaultAudioOutputAlsaName;
        cardName = audioProfile.audioCardName;
        cardProfile = audioProfile.audioCardProfile;
      };
    }
  );

  gameMode = pkgs.writeShellApplication {
    name = "game-mode";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.libnotify
      pkgs.nushell
      pkgs.procps
      pkgs.systemd
      pkgs.util-linux
      switchaudio
    ];
    text = ''
      exec nu ${./game-mode.nu} --config ${configJson} "$@"
    '';
  };
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [ gameMode ];
  };
}
