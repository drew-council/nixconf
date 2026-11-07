{ inputs, ... }:
{
  flake.modules.nixos.desktop-linux = {
    imports = [ inputs.catppuccin.nixosModules.catppuccin ];

    catppuccin = {
      enable = true;
      autoEnable = true;
    };

    qt = {
      enable = true;
      platformTheme = "qt5ct";
      style = "kvantum";
    };
  };

  flake.modules.homeManager.desktop-linux =
    { config, pkgs, ... }:
    let
      cursor = {
        name = "phinger-cursors-light";
        package = pkgs.phinger-cursors;
        size = 24;
      };
    in
    {
      home.pointerCursor = cursor // {
        enable = true;
      };

      gtk = {
        enable = true;
        theme = {
          name = "Adwaita-dark";
          package = pkgs.gnome-themes-extra;
        };
        gtk4.theme = config.gtk.theme;
        cursorTheme = cursor;
      };

      qt = {
        enable = true;
        platformTheme.name = "kvantum";
        style.name = "kvantum";

        # Fixes for Kvantum and the icon theme in KDE applications.
        kde.settings.kdeglobals = {
          UiSettings.ColorScheme = "Kvantum";
          Icons.Theme = "Papirus-Dark";
        };
      };
    };
}
