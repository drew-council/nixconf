{ config, ... }:
let
  inherit (config.my) liveLink;
in
{
  flake.modules.homeManager =
    let
      # GUI on desktops, and the `t3` CLI wherever the server runs.
      package =
        { pkgs, ... }:
        {
          home.packages = [ pkgs.t3code ];
        };
    in
    {
      terminal =
        { config, ... }:
        {
          # Out-of-store links keep the files writable, so edits made in the T3 Code UI land in this repo.
          home.file = {
            ".t3/userdata/settings.json".source = liveLink config ./settings.json;
            ".t3/userdata/client-settings.json".source = liveLink config ./client-settings.json;
            ".t3/userdata/keybindings.json".source = liveLink config ./keybindings.json;
          };
        };

      desktop = package;
      t3code = package;
    };
}
