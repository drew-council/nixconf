{
  lib,
  modulesPath,
  pkgs,
  vars,
  ...
}:

# Cloud dev box on Google Compute Engine. The VM, its persistent /home disk, and
# the working-hours schedule live in Sheer's Pulumi stack (stacks/devbox); this
# is only the OS. The stack boots a small image built from this host without
# Home Manager, then `nixos-rebuild switch` brings it up to the full config.
let
  # Survives image rebuilds, which replace the boot disk.
  persist = "/home/.devbox";
in
{
  imports = [ "${modulesPath}/virtualisation/google-compute-image.nix" ];

  # C4D-class machines expose disks only over NVMe and the NIC only over gVNIC,
  # and boot only UEFI images.
  boot.initrd.availableKernelModules = [
    "nvme"
    "gve"
  ];
  virtualisation.googleComputeImage.efi = true;

  fileSystems."/home" = {
    device = "/dev/disk/by-label/home";
    fsType = "ext4";
    options = [
      "discard"
      "nofail"
    ];
  };

  # Keep the tailnet identity, so a new image is the same Tailscale node.
  fileSystems."/var/lib/tailscale" = {
    device = "${persist}/tailscale";
    fsType = "none";
    options = [
      "bind"
      "nofail"
    ];
    depends = [ "/home" ];
  };
  services.openssh.hostKeys = [
    {
      path = "${persist}/ssh/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];

  services.tailscale = {
    enable = true;
    extraSetFlags = [
      "--operator=${vars.user}"
      "--hostname=devbox-drew"
    ];
  };
  services.t3code.enable = true;

  virtualisation.docker.enable = true;
  # dhcpcd gives interfaces a 169.254.0.0/16 route, which captures the metadata server.
  # That server is also DNS and OS Login, so a running container breaks both.
  networking.dhcpcd.denyInterfaces = [ "veth*" ];
  networking.dhcpcd.extraConfig = "noipv4ll";

  # Home Manager's GTK settings write through dconf.
  programs.dconf.enable = true;

  # The VPC admits only IAP's SSH, and the tailnet is trusted.
  networking.firewall.enable = lib.mkForce false;

  users.users.${vars.user} = {
    uid = 1000;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGogIJ4uaReEMnM8eRedZh0OVq/4AAs4H8xdiWjvf6YF"
    ];
  };
  # OS Login, which keeps `gcloud compute ssh` working, grants sudo through an
  # #includedir that sudo-rs can't parse; use sudo here. The user has no
  # password, and agents run sudo unattended.
  security.sudo-rs.enable = lib.mkForce false;
  security.sudo = {
    enable = lib.mkForce true;
    wheelNeedsPassword = false;
  };

  # Stages this flake's main branch daily for the next boot, which comes on Monday.
  # Switching live would restart services under overnight work.
  system.autoUpgrade = {
    enable = true;
    operation = "boot";
    flake = "github:drew-council/nixconf#devbox";
    dates = "08:50";
    randomizedDelaySec = "5min";
  };

  # The Pulumi stack's startup script exits on NixOS, but its shebang needs bash.
  systemd.services.google-startup-scripts.path = [ pkgs.bash ];

  system.stateVersion = "26.11";
}
