{
  flake.modules.nixos.desktop-linux = {
    # add permissions to access hid device so chrome can read spacemouse device
    services.udev.extraRules =
      let
        group = "users";
      in
      ''
        SUBSYSTEM=="input", GROUP="input", MODE="0666"
        SUBSYSTEM=="usb", ATTRS{idVendor}=="046d", MODE:="0666", GROUP="${group}"
        KERNEL=="hidraw*", ATTRS{idVendor}=="046d", MODE="0666", GROUP="${group}"
        SUBSYSTEM=="usb", ATTRS{idVendor}=="256f", MODE:="0666", GROUP="${group}"
        KERNEL=="hidraw*", ATTRS{idVendor}=="256f", MODE="0666", GROUP="${group}"
      '';
  };
}
