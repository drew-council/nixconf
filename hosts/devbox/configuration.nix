{
  lib,
  modulesPath,
  pkgs,
  vars,
  ...
}:

# Cloud dev box on Google Compute Engine. The VM, its persistent /home disk, and
# the weekday schedule live in Sheer's Pulumi stack (stacks/devbox); this is only
# the OS.
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

  # XFS so the Bazel disk cache and output bases share blocks through reflinks.
  # Both must stay on this filesystem. See stacks/devbox/README.md in sheer.
  fileSystems."/home" = {
    device = "/dev/disk/by-label/home-xfs";
    fsType = "xfs";
    options = [
      "discard"
      "nofail"
      # A disk restored from a snapshot can be larger than its filesystem.
      "x-systemd.growfs"
    ];
  };

  # The bind sources below must exist before their mounts, including on a home
  # disk restored from a snapshot older than one of them.
  systemd.services.devbox-persist-dirs = {
    description = "Create the persistent directories on the home disk";
    wantedBy = [ "local-fs.target" ];
    after = [ "home.mount" ];
    before = [
      "var-lib-tailscale.mount"
      "var-tmp-_bazel_${vars.user}.mount"
    ];
    unitConfig = {
      DefaultDependencies = false;
      RequiresMountsFor = "/home";
    };
    serviceConfig.Type = "oneshot";
    script = ''
      ${pkgs.coreutils}/bin/install -d -m 700 ${persist} ${persist}/ssh ${persist}/tailscale
      ${pkgs.coreutils}/bin/install -d -o 1000 -g 100 -m 755 ${persist}/bazel
    '';
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
  # Output bases reach tens of GB per worktree, so they belong on the home disk.
  # The bind keeps the path that .bazelrc and bazelprune use.
  fileSystems."/var/tmp/_bazel_${vars.user}" = {
    device = "${persist}/bazel";
    fsType = "none";
    options = [
      "bind"
      "nofail"
    ];
    depends = [ "/home" ];
  };
  # The home NAS is LAN only, and this box is not on that LAN.
  fileSystems."/mnt/tungsten-vault".enable = false;

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

  system.stateVersion = "26.11";
}
