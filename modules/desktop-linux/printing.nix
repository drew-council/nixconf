{
  flake.modules.nixos.desktop-linux =
    { pkgs, ... }:
    {
      # Detect network printers
      services.avahi = {
        enable = true;
        nssmdns4 = true;
        openFirewall = true;
      };

      services.printing = {
        enable = true;
        # network drivers
        drivers = with pkgs; [
          cups-filters
          cups-browsed
        ];
      };

      environment.systemPackages = [
        pkgs.system-config-printer # printer setup GUI
      ];
    };
}
