{ config, vars, ... }:
let
  # Out-of-store links keep the files writable, so edits made in the T3 Code UI land in this repo.
  link = name: config.lib.file.mkOutOfStoreSymlink "${vars.flakePath}/home/programs/t3code/${name}";
in
{
  home.file = builtins.listToAttrs (
    map
      (name: {
        name = ".t3/userdata/${name}";
        value.source = link name;
      })
      [
        "settings.json"
        "client-settings.json"
        "keybindings.json"
      ]
  );
}
