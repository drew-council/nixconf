# ttrpgui: `ttrpgui` installs the app, whose start page opens a Game, hosts a
# display, or joins one on the LAN. `ttrpgui-host` lets the home LAN reach a
# hosted display.
{ inputs, ... }:
{
  flake.modules.homeManager.ttrpgui =
    { pkgs, ... }:
    {
      home.packages = [ inputs.ttrpgui.packages.${pkgs.stdenv.hostPlatform.system}.default ];
    };

  # LAN only, like the other LAN services. 7373 is the app's port.
  flake.modules.nixos.ttrpgui-host.networking.firewall.extraCommands = ''
    iptables -A nixos-fw -s 192.168.1.0/24 -p tcp --dport 7373 -j nixos-fw-accept
  '';
}
