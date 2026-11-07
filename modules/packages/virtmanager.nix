{
  vars,
  ...
}:
{
  programs.virt-manager.enable = true;

  users.groups.libvirtd.members = [ vars.user ];

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
}
