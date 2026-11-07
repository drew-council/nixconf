{
  config,
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
    ./packages/terminal.nix
  ];

  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
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

  services.clamav = {
    daemon.enable = false;
    scanner.enable = false;
    updater.enable = false;
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

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = false;
  services.pipewire.enable = false;

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
      PermitRootLogin = "prohibit-password";
    };
  };

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
  networking.firewall.enable = true;
}
