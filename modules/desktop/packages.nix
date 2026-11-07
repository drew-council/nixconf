{
  # GUI apps shared by Linux and macOS. On macOS, Home Manager copies their
  # .app bundles into ~/Applications/Home Manager Apps (targets.darwin.copyApps).
  flake.modules.homeManager.desktop =
    { pkgs, ... }:
    {
      home.packages = [
        pkgs.gchat-desktop # electron wrapper for google chat
      ];
    };

  # Linux gets these from modules/desktop-linux/packages.nix.
  flake.modules.homeManager.desktop-macos =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        zed-editor
        ytmdesktop # desktop app for youtube music
      ];
    };
}
