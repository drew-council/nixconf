let
  defaults = import ./_defaults.nix;
in
{
  flake.modules.homeManager.desktop =
    { lib, pkgs, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
    in
    {
      programs.ghostty = {
        enable = true;
        settings = {
          # GUI-launched Ghostty on macOS does not inherit the Nix profile PATH.
          command = if isDarwin then lib.getExe pkgs.nushell else "nu";

          font-family = defaults.fontFamily;
          font-size = defaults.fontSize;
          background-opacity = if isDarwin then 1.0 else defaults.backgroundOpacity;
          cursor-style = "bar";
          cursor-style-blink = false;
          adjust-cursor-thickness = 2;
          shell-integration-features = "no-cursor";
          keybind = [
            "ctrl+enter=unbind"
            "ctrl+shift+enter=unbind"
          ]
          # Linux-style clipboard keys; Karabiner leaves terminals alone, so
          # Ctrl+C still reaches the shell.
          ++ lib.optionals isDarwin [
            "ctrl+shift+c=copy_to_clipboard"
            "ctrl+shift+v=paste_from_clipboard"
            # macOS defaults map these to esc:b/esc:f, which herdr reads as alt+b/alt+f.
            "alt+arrow_left=unbind"
            "alt+arrow_right=unbind"
          ];

          copy-on-select = "clipboard";
          app-notifications = "no-clipboard-copy";
          confirm-close-surface = false;
          link-url = true;

          # On Linux the catppuccin module supplies the theme.
          theme = lib.mkIf isDarwin "Catppuccin Mocha";
        };
        enableBashIntegration = false;
        enableZshIntegration = true;
        enableFishIntegration = true;
        package = if isLinux then pkgs.ghostty else null;
      };
    };
}
