let
  defaults = import ./_defaults.nix;
in
{
  flake.modules.homeManager.desktop-linux =
    { lib, pkgs, ... }:
    {
      programs.kitty = {
        enable = true;
        font = {
          name = defaults.fontFamily;
          size = defaults.fontSize;
        };
        shellIntegration = {
          enableBashIntegration = false;
          enableZshIntegration = true;
        };

        settings = {
          copy_on_select = "clipboard";
          clear_selection_on_clipboard_loss = true;
          paste_actions = "quote-urls-at-prompt,confirm,confirm-if-large";

          shell = "nu";

          cursor_shape = "beam";
          cursor_blink_interval = 0;

          background_opacity = defaults.backgroundOpacity;
          enable_audio_bell = false;

          scrollback_lines = defaults.scrollback;
          scrollback_fill_enlarged_window = true;
          focus_follows_mouse = true;

          confirm_os_window_close = 0;

          allow_remote_control = true;

          # configure using neovim as scrollback pager
          scrollback_pager =
            let
              pager = pkgs.writeShellApplication {
                name = "nvim-pager";
                text = builtins.readFile ./kitty_nvim_pager.sh;
              };
            in
            "${pager}/bin/nvim-pager 'INPUT_LINE_NUMBER' 'CURSOR_LINE' 'CURSOR_COLUMN'";
        };

        keybindings = {
          "ctrl+shift+t" = "launch --type=tab --cwd=last_reported";
          "ctrl+shift+space" = "send_text all lg\\r";
          "ctrl+shift+b" = "send_text all zig build\\r";
          "super+t" = "launch --type=tab --cwd=last_reported";
          "super+h" = "remote_control_script ${lib.getExe pkgs.kitty-hypr-nav} kitty-left";
          "super+l" = "remote_control_script ${lib.getExe pkgs.kitty-hypr-nav} kitty-right";
          "super+w" = "remote_control_script ${lib.getExe pkgs.kitty-hypr-nav} kitty-close-tab";
        };
      };
    };
}
