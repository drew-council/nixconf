{
  flake.modules.nixos.home-lan = {
    networking.nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];

    # Mount NAS, optional for boot
    fileSystems."/mnt/tungsten-vault" = {
      device = "192.168.1.202:/mnt/tungsten/tungsten-vault";
      fsType = "nfs";
      options = [
        "x-systemd.automount"
        "noauto"
      ];
    };
  };
}
