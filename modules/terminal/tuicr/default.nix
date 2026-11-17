{
  flake.modules.homeManager.terminal =
    { pkgs, ... }:
    let
      # tuicr loads `syntaxes/*.sublime-syntax` from its config dir at startup.
      nushell-sublime-syntax = pkgs.fetchFromGitHub {
        owner = "kurokirasama";
        repo = "nushell_sublime_syntax";
        rev = "8a1bb9205859d0c2f362c6c5a2b7ef1a7a87c387";
        hash = "sha256-2A7c6/FOsOyzyGAshZJZvZ/m5w1cKj7uckB+pzdlr3M=";
      };
    in
    {
      home.packages = [ pkgs.tuicr ];

      xdg.configFile."tuicr/config.toml".source = ./config.toml;
      xdg.configFile."tuicr/review_guide_prompt.md".source = ./review_guide_prompt.md;
      xdg.configFile."tuicr/syntaxes/nushell.sublime-syntax".source =
        "${nushell-sublime-syntax}/nushell.sublime-syntax";
    };
}
