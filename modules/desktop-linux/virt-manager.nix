{
  flake.modules.nixos.desktop-linux =
    { config, ... }:
    {
      programs.virt-manager.enable = true;

      users.groups.libvirtd.members = [ config.my.user.name ];

      virtualisation = {
        libvirtd = {
          enable = true;
          qemu = {
            # enable software TPM emulation for Windows 11
            swtpm.enable = true;
          };
        };
        spiceUSBRedirection.enable = true;
      };
    };
}
