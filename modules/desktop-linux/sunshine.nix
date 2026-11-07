{
  flake.modules = {
    nixos.desktop-linux = {
      # low-latency desktop/game streaming
      services.sunshine = {
        enable = true;
        autoStart = false;
        openFirewall = true;
      };
    };

    homeManager.desktop-linux =
      { lib, pkgs, ... }:
      {
        systemd.user.services.sunshine-tablet = {
          Unit = {
            Description = "Sunshine tablet stream";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
            Conflicts = [ "sunshine.service" ];
          };
          Service = {
            # output_name must match the headless output Hyprland creates.
            ExecStart = "${lib.getExe pkgs.sunshine} capture=wlr output_name=HEADLESS-TABLET";
            Restart = "on-failure";
            RestartSec = 5;
          };
        };
      };
  };
}
