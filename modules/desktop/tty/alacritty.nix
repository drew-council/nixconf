let
  defaults = import ./_defaults.nix;
in
{
  flake.modules.homeManager.desktop-linux.programs.alacritty = {
    enable = true;
    settings = {
      window = {
        opacity = defaults.backgroundOpacity;

        padding = {
          x = 10;
          y = 10;
        };
        dynamic_padding = true;
      };

      scrolling.history = defaults.scrollback;

      selection.save_to_clipboard = true;

      terminal.shell.program = "nu";

      cursor = {
        style = {
          shape = "Beam";
          blinking = "Off";
        };
        unfocused_hollow = true;
      };

      font = {
        normal = {
          family = defaults.fontFamily;
          style = "Regular";
        };
        bold = {
          family = defaults.fontFamily;
          style = "Bold";
        };
        italic = {
          family = defaults.fontFamily;
          style = "Italic";
        };
        bold_italic = {
          family = defaults.fontFamily;
          style = "Bold Italic";
        };
        size = defaults.fontSize;
      };
    };
  };
}
