# ttrpgui across two machines: igneous shows the player display and plays the
# music, a laptop drives it with the control window. Every host that runs it
# lists `ttrpgui`, plus `ttrpgui-display` or `ttrpgui-remote` for its role.
{ inputs, ... }:
let
  port = 7373;
  # igneous on the home LAN, as in desktop/ssh.nix.
  displayHost = "192.168.1.123";

  package = pkgs: inputs.ttrpgui.packages.${pkgs.stdenv.hostPlatform.system}.default;

  entry = pkgs: name: comment: args: {
    inherit name comment;
    exec = "${pkgs.lib.getExe (package pkgs)} ${args}";
    icon = "ttrpgui";
    categories = [
      "Game"
      "RolePlaying"
    ];
    settings.StartupWMClass = "ttrpgui";
  };
in
{
  flake.modules.homeManager.ttrpgui =
    { pkgs, ... }:
    {
      home.packages = [ (package pkgs) ];
    };

  flake.modules.homeManager.ttrpgui-display =
    { pkgs, ... }:
    {
      xdg.desktopEntries.ttrpgui-display =
        entry pkgs "ttrpgui display" "Show the player display to the LAN"
          "--lan --display --port ${toString port}";
    };

  # LAN only, like the other LAN services.
  flake.modules.nixos.ttrpgui-display.networking.firewall.extraCommands = ''
    iptables -A nixos-fw -s 192.168.1.0/24 -p tcp --dport ${toString port} -j nixos-fw-accept
  '';

  flake.modules.homeManager.ttrpgui-remote =
    { pkgs, ... }:
    {
      xdg.desktopEntries.ttrpgui-remote =
        entry pkgs "ttrpgui remote" "Run the game on igneous's display"
          "--connect http://${displayHost}:${toString port}";
    };
}
