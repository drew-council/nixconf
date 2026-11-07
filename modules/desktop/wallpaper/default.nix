let
  wallpaper = ./purple_crystals.jpg;
in
{
  flake.modules.homeManager.desktop-linux = {
    services.hyprpaper = {
      enable = true;
      settings = {
        wallpaper = [
          {
            monitor = "";
            path = "${wallpaper}";
          }
        ];
        splash = false;
      };
    };
  };

  flake.modules.homeManager.desktop-macos =
    { lib, ... }:
    {
      home.activation.setWallpaper = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run /usr/bin/osascript -e 'tell application "System Events" to tell every desktop to set picture to "${wallpaper}"'
      '';
    };
}
