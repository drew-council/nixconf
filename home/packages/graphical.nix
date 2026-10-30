{
  lib,
  pkgs,
  platform,
  ...
}:
{
  # GUI apps shared by Linux and macOS. On macOS, Home Manager copies their
  # .app bundles into ~/Applications/Home Manager Apps (targets.darwin.copyApps).
  home.packages =
    with pkgs;
    [
      gchat-desktop # electron wrapper for google chat
      t3code # coding agent GUI; launch with `t3code-desktop`, CLI is `t3`
    ]
    # Linux gets these from modules/packages/graphical.nix.
    ++ lib.optionals platform.isDarwin [
      zed-editor # Zed fork (overlays.nix); lands as "Zed Nightly.app", CLI is `zed`
      ytmdesktop # desktop app for youtube music
    ];
}
