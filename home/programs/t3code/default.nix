{
  config,
  vars,
  ...
}:
let
  # T3 Code rewrites these from its settings UI, so link them writable into
  # this checkout. T3 resolves the symlink on save and keeps it intact.
  link = name: config.lib.file.mkOutOfStoreSymlink "${vars.flakePath}/home/programs/t3code/${name}";
in
{
  home.file = {
    ".t3/userdata/settings.json".source = link "settings.json";
    ".t3/userdata/keybindings.json".source = link "keybindings.json";
    # Published environment themes. T3 rejects symlinked theme files, so the
    # directory is linked instead.
    ".t3/userdata/themes".source = link "themes";
  };
}
