{
  flake.modules.nixos.terminal.virtualisation = {
    docker = {
      enable = true;
      rootless = {
        enable = true;
        setSocketVariable = true;
      };
    };
    podman = {
      enable = true;
      autoPrune.enable = true;
    };
  };
}
