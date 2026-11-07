{ lib, ... }:
{
  options.my.user = lib.mkOption { type = lib.types.attrs; };

  config = {
    my.user = {
      name = "drew";
      backupFileExtension = "hmbackup";
      sshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGogIJ4uaReEMnM8eRedZh0OVq/4AAs4H8xdiWjvf6YF";
    };

    flake.modules = {
      nixos.base =
        { config, ... }:
        {
          users.users.${config.my.user.name} = {
            isNormalUser = true;
            description = config.my.user.name;
            extraGroups = [
              "networkmanager"
              "wheel"
              "docker"
              "cdrom"
            ];
          };
        };

      darwin.base =
        { config, pkgs, ... }:
        {
          system.primaryUser = config.my.user.name;

          users.users.${config.my.user.name} = {
            inherit (config.my.user) home;
            shell = pkgs.zsh;
          };
        };

      homeManager.base =
        { config, ... }:
        {
          home = {
            username = config.my.user.name;
            homeDirectory = config.my.user.home;

            # The Home Manager release this configuration is compatible with.
            # Check the release notes before changing it, even when updating
            # Home Manager.
            stateVersion = "26.05";

            sessionPath = [
              "${config.my.user.home}/.cargo/bin" # programs from `cargo install`
            ];
          };

          programs.home-manager.enable = true;
        };
    };
  };
}
