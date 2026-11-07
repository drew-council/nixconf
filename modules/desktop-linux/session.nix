{
  flake.modules.homeManager.desktop-linux =
    { config, ... }:
    {
      programs.fuzzel = {
        enable = true;
        settings = {
          main = {
            # Close Fuzzel when clicking outside it.
            "keyboard-focus" = "on-demand";
            "exit-on-keyboard-focus-loss" = true;
          };
          "border" = {
            "width" = 3;
          };
        };
      };
      services.swaync = {
        enable = true;
      };

      dconf = {
        enable = true;
        settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";
      };

      home = {
        sessionVariables = {
          BROWSER = "zen-beta";
          GTK_USE_PORTAL = "1";
          HYPRSHOT_DIR = "${config.my.user.home}/Pictures/screenshots";
        };
        shellAliases = {
          e = "zeditor --new .";
          zed = "zeditor";
        };
      };
    };
}
