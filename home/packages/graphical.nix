{
  pkgs,
  ...
}:
{
  # GUI apps shared by Linux and macOS. On macOS, Home Manager copies their
  # .app bundles into ~/Applications/Home Manager Apps (targets.darwin.copyApps).
  home.packages = with pkgs; [
    gchat-desktop # electron wrapper for google chat
  ];
}
