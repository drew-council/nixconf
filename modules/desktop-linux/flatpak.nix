{ inputs, ... }:
{
  flake.modules.nixos.desktop-linux = {
    imports = [ inputs.nix-flatpak.nixosModules.nix-flatpak ];

    services.flatpak = {
      enable = true;
      update.auto = {
        enable = true;
        onCalendar = "weekly";
      };

      packages = [
        "com.obsproject.Studio"
        "com.github.tchx84.Flatseal"
        "com.makemkv.MakeMKV"
      ];
    };
  };
}
