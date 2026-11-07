let
  wallpaper =
    pkgs:
    pkgs.fetchurl {
      url = "https://filedn.com/l0xkAHTdfcEJNc2OW7dfBny/purple_crystals.jpg";
      sha256 = "0fyrzlbx6ii9nzpn2vpl45vdq9hh87af18d3sjpvv66cbsc9vwga";
    };
in
{
  flake.modules.homeManager.desktop-linux =
    { pkgs, ... }:
    {
      services.hyprpaper = {
        enable = true;
        settings = {
          wallpaper = [
            {
              monitor = "";
              path = (wallpaper pkgs).outPath;
            }
          ];
          splash = false;
        };
      };
    };

  flake.modules.homeManager.desktop-macos =
    { lib, pkgs, ... }:
    {
      home.activation.setWallpaper = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run /usr/bin/osascript -e 'tell application "System Events" to tell every desktop to set picture to "${wallpaper pkgs}"'
      '';
    };
}
