{
  flake.modules.nixos.desktop-linux =
    { config, pkgs, ... }:
    {
      users.users.${config.my.user.name}.extraGroups = [ "input" ];

      boot.loader = {
        systemd-boot = {
          enable = true;
          configurationLimit = 8;
        };
        efi.canTouchEfiVariables = true;
      };

      networking.networkmanager.enable = true;
      networking.firewall.enable = false;

      services.xserver = {
        enable = true;
        xkb = {
          layout = "us";
          variant = "";
        };
      };

      # Detect network printers
      services.avahi = {
        enable = true;
        nssmdns4 = true;
        openFirewall = true;
      };

      services.printing = {
        enable = true;
        # network drivers
        drivers = with pkgs; [
          cups-filters
          cups-browsed
        ];
      };

      hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
      };

      # service to allow automount USB drives
      services.udisks2.enable = true;

      services.pulseaudio.enable = false;
      security.rtkit.enable = true;
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
      };

      security.chromiumSuidSandbox.enable = true;

      hardware.graphics = {
        enable = true;
        enable32Bit = true;
      };

      services.mullvad-vpn = {
        enable = true;
        gui.enable = true;
      };
    };
}
