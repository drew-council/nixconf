{
  pkgs,
  lib,
  vars,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./silksong-archipelago.nix
  ];

  boot = {
    # Test the initial AMDGPU HDMI 2.1 FRL support in Linux 7.2.
    kernelPackages = pkgs.linuxPackages_testing;
    kernelParams = [ "amdgpu.dcfeaturemask=0x400" ];
    # start amd driver at boot
    initrd.kernelModules = [ "amdgpu" ];
    # enable kernel for disc drive
    kernelModules = [ "sg" ];
    # support ntfs for mounting windows partition
    supportedFilesystems = [ "ntfs" ];
  };

  hardware.graphics.extraPackages = with pkgs; [ rocmPackages.clr.icd ];

  environment.systemPackages = with pkgs; [
    amd-ctk
    amd-container-runtime
    lumafly
  ];
  virtualisation.docker.daemon.settings.runtimes.amd = {
    path = lib.getExe pkgs.amd-container-runtime;
  };

  services.ollama = {
    enable = false;
    openFirewall = true;
    environmentVariables = {
      OLLAMA_MODELS = "/mnt/storage/ollama";
    };
  };

  # Homarr system health and resource monitoring. The web UI is disabled;
  # Homarr only needs the Glances v4 API on the LAN.
  services.glances = {
    enable = true;
    openFirewall = true;
    extraArgs = [
      "--webserver"
      "--disable-webui"
    ];
  };

  # ghostty-web provides a real shell without login authentication, so this
  # port must only be reachable from the trusted LAN.
  services.herdr-web.enable = true;

  networking.firewall = {
    enable = lib.mkForce true;
    allowedTCPPorts = [
      41707 # pi remote-control
    ];
  };

  # Temporarily keep Tailscale from starting during remote activation.
  systemd.services.tailscaled.wantedBy = lib.mkForce [ ];

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      AuthenticationMethods = "publickey";
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      PubkeyAuthentication = true;
    };
  };

  users.users."${vars.user}".openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGogIJ4uaReEMnM8eRedZh0OVq/4AAs4H8xdiWjvf6YF"
  ];

  fileSystems = {
    # mount windows partition
    "/mnt/windows" = {
      device = "/dev/disk/by-uuid/5E06928506925DB9";
      fsType = "ntfs";
      options = [
        "rw"
        "uid=1000"
        "gid=100"
      ];
    };

    # mount storage drive
    "/mnt/storage" = {
      device = "/dev/disk/by-uuid/6422C81A22C7EF5C";
      fsType = "ntfs";
      options = [
        "rw"
        "uid=1000"
        "gid=100"
      ];
    };
  };

  # fix clock for windows dual boot
  time.hardwareClockInLocalTime = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?

}
