{
  config,
  pkgs,
  platform,
  ...
}:

let
  yaml = pkgs.formats.yaml { };
in
{
  xdg.configFile."glow/glow.yml".source = yaml.generate "glow.yml" {
    style =
      if platform.isLinux then
        "${config.catppuccin.sources.glamour}/catppuccin-${config.catppuccin.flavor}.json"
      else
        "dark";
    pager = true;
    width = 100;
  };
}
