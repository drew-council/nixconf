{
  flake.modules.nixos.desktop-linux.services.mullvad-vpn = {
    enable = true;
    gui.enable = true;
  };
}
