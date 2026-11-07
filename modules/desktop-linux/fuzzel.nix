{
  flake.modules.homeManager.desktop-linux.programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        # Close Fuzzel when clicking outside it.
        "keyboard-focus" = "on-demand";
        "exit-on-keyboard-focus-loss" = true;
      };
      "border" = {
        "width" = 3;
      };
    };
  };
}
