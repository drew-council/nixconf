{
  flake.modules.nixos.desktop-linux.services.xserver = {
    enable = true;
    xkb = {
      layout = "us";
      variant = "";
    };
  };
}
