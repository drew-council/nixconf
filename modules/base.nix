{
  config,
  inputs,
  lib,
  pkgs,
  vars,
  ...
}:

let
  substitutersConfig = builtins.fromJSON (builtins.readFile ../substituters_config.json);
in
{
  imports = [
    inputs.home-manager.nixosModules.default
    ./displaymanager.nix
    ./fhs-shebangs.nix
    ./herdr-web.nix
    ./laptop.nix
    ./nvidia.nix
    ./remote-desktop.nix
    ./windowmanager.nix
    ./packages/terminal.nix
    ./packages/graphical.nix
  ];

  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

  boot.kernel.sysctl = {
    # Raise the inotify watch limit for large workspaces and dev tools.
    "fs.inotify.max_user_watches" = 4 * 1024 * 1024;
  };

  # Bootloader.
  boot.loader = {
    systemd-boot = {
      enable = true;
      configurationLimit = 8;
    };
    efi.canTouchEfiVariables = true;
  };

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];

    trusted-users = [
      "root"
      "@wheel"
    ];
  }
  // lib.getAttrs [
    "extra-substituters"
    "extra-trusted-substituters"
    "extra-trusted-public-keys"
  ] substitutersConfig;

  programs.nix-ld = {
    enable = true;
    # libraries = with pkgs; [
    #   # Add any missing dynamic libraries for unpackaged
    #   # programs here, NOT in environment.systemPackages
    # ];
  };

  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Make Tailscale available on personal machines.
  services.tailscale.enable = lib.mkIf (vars.isPersonal config) true;

  # set DNS servers on non-work machines only
  networking.nameservers = lib.mkIf (vars.isPersonal config) [
    "1.1.1.1"
    "8.8.8.8"
  ];

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Select internationalisation properties.
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

  # Enable the X11 windowing system.
  # You can disable this if you're only using the Wayland session.
  services.xserver = {
    enable = true;

    # Configure keymap in X11
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

  # Enable CUPS to print documents.
  services.printing = {
    enable = true;
    # network drivers
    drivers = with pkgs; [
      cups-filters
      cups-browsed
    ];
  };

  services.clamav =
    let
      enabled = !(vars.isPersonal config);
    in
    {
      daemon.enable = enabled;
      scanner.enable = enabled;
      updater.enable = enabled;
    };

  hardware.bluetooth = {
    enable = true; # enables support for Bluetooth
    powerOnBoot = true; # powers up the default Bluetooth controller on boot
  };

  # security.polkit = {
  #   enable = true;
  #   extraConfig = ''
  #   polkit.addRule(function(action, subject) {
  #     if (
  #       subject.isInGroup("users")
  #         && (
  #           action.id == "org.freedesktop.login1.reboot" ||
  #           action.id == "org.freedesktop.login1.reboot-multiple-sessions" ||
  #           action.id == "org.freedesktop.login1.power-off" ||
  #           action.id == "org.freedesktop.login1.power-off-multiple-sessions"
  #         )
  #       )
  #     {
  #       return polkit.Result.YES;
  #     }
  #   });
  #   '';
  # };

  # use sudo-rs instead of default sudo
  security = {
    sudo.enable = false;
    sudo-rs = {
      enable = true;
      execWheelOnly = true;
      wheelNeedsPassword = true;
    };
  };

  # service to allow automount USB drives
  services.udisks2.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users."${vars.user}" = {
    isNormalUser = true;
    description = vars.user;
    extraGroups = [
      "networkmanager"
      "wheel"
      "docker"
      "cdrom"
      "input"
    ];
    # packages = with pkgs; [
    # ];
  };

  # Remap CAPS lock to ESC
  # TODO: find more nixos-way to do this, maybe use Kanata?
  services.udev.extraHwdb = ''
    evdev:atkbd:*
      KEYBOARD_KEY_3a=esc
  '';

  # Mount NAS, optional for boot
  fileSystems."/mnt/tungsten-vault" = lib.mkIf (vars.isPersonal config) {
    device = "192.168.1.202:/mnt/tungsten/tungsten-vault";
    fsType = "nfs";
    options = [
      "x-systemd.automount"
      "noauto"
    ];
  };

  # Enable SSH
  services.openssh = {
    enable = true;
    ports = [ 22 ];
    settings = {
      PasswordAuthentication = false;
      AllowUsers = null; # Allows all users by default. Can be [ "user1" "user2" ]
      UseDns = true;
      X11Forwarding = false;
      PermitRootLogin = "no"; # "yes", "without-password", "prohibit-password", "forced-commands-only", "no"
    };
  };

  # add pocl to always have cpu opencl support at minimum
  hardware.graphics.extraPackages = with pkgs; [ pocl ];

  security.chromiumSuidSandbox.enable = true;

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;
}
