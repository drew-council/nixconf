{
  flake.modules.nixos.laptop = {
    powerManagement = {
      enable = true;
      powertop.enable = true;
    };
  };
}
