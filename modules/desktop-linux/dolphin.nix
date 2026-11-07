{
  flake.modules.nixos.desktop-linux =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        pkgs.kdePackages.dolphin # preferred file manager
      ];

      # fix dolphin default programs
      # https://discourse.nixos.org/t/dolphin-does-not-have-mime-associations/48985/8
      environment.etc."/xdg/menus/applications.menu".text =
        builtins.readFile "${pkgs.kdePackages.plasma-workspace}/etc/xdg/menus/plasma-applications.menu";
    };
}
