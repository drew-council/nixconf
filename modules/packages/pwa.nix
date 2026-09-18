{
  pkgs,
  lib,
  ...
}:
let
  # modified from https://github.com/bjornfor/nixos-config/blob/master/lib/default.nix
  makeWebApp =
    {
      name,
      url,
      startupWMClass ? "${name} ${url}",
      icon ? null,
      categories ? null,
      browser ? "chromium-browser",
      darkMode ? true,
    }:
    pkgs.makeDesktopItem (
      let
        darkModeArgs = if darkMode then "--force-dark-mode --enable-features=WebUIDarkMode " else "";
        exec = "${browser} ${darkModeArgs}--app=${url}/";
      in
      {
        inherit name startupWMClass exec;
        comment = name;
        desktopName = name;
      }
      // (if icon != null then { inherit icon; } else { })
      // (if categories != null then { inherit categories; } else { })
    );

  webApps = map makeWebApp [
    {
      name = "Linear";
      url = "https://linear.app";
    }
    {
      name = "GitHub";
      url = "https://github.com";
    }
    {
      name = "Google Calendar";
      url = "https://calendar.google.com";
    }
    {
      name = "Google Chat";
      url = "https://chat.google.com";
    }
    {
      name = "T3 Chat";
      url = "https://t3.chat";
    }
  ];
in
{
  environment.systemPackages = lib.mkAfter webApps;
}
