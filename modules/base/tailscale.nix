{
  flake.modules.nixos.base =
    { config, ... }:
    {
      services.tailscale = {
        enable = true;
        # Lets user processes such as T3 Code run `tailscale serve` without root.
        extraSetFlags = [ "--operator=${config.my.user.name}" ];
      };
    };
}
