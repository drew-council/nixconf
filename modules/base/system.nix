{
  flake.modules.nixos.base =
    { lib, pkgs, ... }:
    {
      boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

      boot.kernel.sysctl = {
        # Raise the inotify watch limit for large workspaces and dev tools.
        "fs.inotify.max_user_watches" = 4 * 1024 * 1024;
      };

      time.timeZone = "America/New_York";

      i18n = {
        defaultLocale = "en_US.UTF-8";
        extraLocaleSettings = {
          LC_ADDRESS = "en_US.UTF-8";
          LC_IDENTIFICATION = "en_US.UTF-8";
          LC_MEASUREMENT = "en_US.UTF-8";
          LC_MONETARY = "en_US.UTF-8";
          LC_NAME = "en_US.UTF-8";
          LC_NUMERIC = "en_US.UTF-8";
          LC_PAPER = "en_US.UTF-8";
          LC_TELEPHONE = "en_US.UTF-8";
          LC_TIME = "en_US.UTF-8";
        };
      };

      # use sudo-rs instead of default sudo
      security = {
        sudo.enable = false;
        sudo-rs = {
          enable = true;
          execWheelOnly = true;
          wheelNeedsPassword = true;
        };
      };

      # Remap CAPS lock to ESC
      # TODO: find more nixos-way to do this, maybe use Kanata?
      services.udev.extraHwdb = ''
        evdev:atkbd:*
          KEYBOARD_KEY_3a=esc
      '';

      # Register zsh system-wide and make it the default login shell.
      programs.zsh.enable = true;
      users.defaultUserShell = pkgs.zsh;

      # Keep privileged machine-administration tools in the system profile so they
      # remain available through sudo's restricted PATH. User tools live in Home
      # Manager under modules/terminal/packages.nix.
      environment.systemPackages = with pkgs; [
        hwinfo
        lshw
        traceroute
        atop
        iftop
        iotop
        sysdig
        perf
        exfatprogs
        linuxConsoleTools
        caligula
      ];
    };
}
