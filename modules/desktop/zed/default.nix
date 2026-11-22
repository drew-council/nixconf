# Zed only reads the fixed `.json` names, so the `.jsonc` sources are linked under those.
# It rewrites these files from its settings UI, following symlinks.
# Live links let those writes land in this repo for review.
{ config, ... }:
let
  inherit (config.my) liveLink;
in
{
  flake.modules.homeManager.desktop =
    { config, ... }:
    {
      xdg.configFile = {
        "zed/settings.json".source = liveLink config ./settings.jsonc;
        "zed/keymap.json".source = liveLink config ./keymap.jsonc;
        "zed/tasks.json".source = liveLink config ./tasks.jsonc;
      };
    };
}
