{ pkgs, ... }:
{
  home.packages = [ pkgs.tuicr ];

  xdg.configFile."tuicr/config.toml".source = ./config.toml;
  xdg.configFile."tuicr/review_guide_prompt.md".source = ./review_guide_prompt.md;
}
