# OmniWM owns settings.toml: its Settings window and schema migrations rewrite
# the file in place, following symlinks. A live link lets those writes land in
# this repo for review. OmniWM strips comments on rewrite, so the reasoning
# behind the non-default values lives here:
#
# - Mirrors ../../desktop-linux/hyprland, with Command standing in for SUPER.
#   Option belongs to herdr's alt+... bindings, so no hotkey uses it.
# - Karabiner turns Control+K/L into Command+K/L for apps, which OmniWM can't
#   tell from the real keys. focus.up and focus.right stay unassigned and
#   Karabiner runs them through omniwmctl (../karabiner).
# - gaps.outer.top is measured from the top of the display, so it includes the
#   24pt menu bar.
# - Column scrolling is off: its swipe would clash with the three-finger
#   workspace swipe, whose macOS counterpart is disabled in ../system.nix.
# - Update checks are off because Nix pins the version. IPC is on for
#   omniwmctl.
{ config, ... }:
let
  inherit (config.my) liveLink;
in
{
  flake.modules.homeManager.desktop-macos =
    { config, ... }:
    {
      programs.omniwm.enable = true;

      xdg.configFile."omniwm/settings.toml".source = liveLink config ./settings.toml;

      # Without a ProcessType, launchd throttles the agent as background work
      # (scheduling priority 20 vs 46+ for apps), so OmniWM stalls under load.
      launchd.agents.omniwm.config.ProcessType = "Interactive";
    };
}
