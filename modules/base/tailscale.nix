{
  flake.modules.nixos.base =
    { config, ... }:
    {
      services.tailscale = {
        enable = true;
        # Lets user processes run `tailscale serve` without root.
        extraSetFlags = [ "--operator=${config.my.user.name}" ];
      };
    };
}
