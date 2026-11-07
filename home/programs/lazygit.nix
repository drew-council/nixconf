{
  config,
  lib,
  pkgs,
  platform,
  ...
}:
let
  mkLazyAppConfigValidation = import ./lazy-app-validation.nix { inherit lib pkgs; };
in
{
  programs.lazygit = {
    enable = true;
    # I do my own integration, don't want this
    enableBashIntegration = false;
    enableZshIntegration = false;
    enableNushellIntegration = false;
    settings = {
      nerdFontsVersion = "3";
      showFileIcons = true;
      skipNoStagedFilesWarning = true;
      language = "en";
      update.method = "never";
      disableStartupPopups = true;
      notARepository = "quit";

      os = {
        editPreset = if platform.isDarwin then "nvim" else "zed";

        # Use a newline-free pipeline supported by both GNU and BSD base64.
        copyToClipboardCmd = ''
          if [[ "$TERM" =~ ^(screen|tmux) ]]; then
            printf "\033Ptmux;\033\033]52;c;$(printf {{text}} | base64 | tr -d '\n')\a\033\\" > /dev/tty
          else
            printf "\033]52;c;$(printf {{text}} | base64 | tr -d '\n')\a" > /dev/tty
          fi
        '';
      };

      # skips drop to terminal from signing commit
      promptToReturnFromSubprocess = false;
      skipHookPrefix = "-";

      git = {
        # allow rewording of signed commits, I use op as ssh signing agent
        overrideGpg = true;
        diffRenderers = [
          {
            colorArg = "always";
            command = "delta --dark --paging=never";
          }
        ];
        # parseEmoji = true;
      };

      customCommands = [
        {
          # <c-f> is a built-in Lazygit binding for findBaseCommitForFixup
          # in files/commit views, so use uppercase F as the mnemonic key for format.
          key = "F";
          context = "global";
          command = "nix fmt";
          description = "Run nix fmt";
          loadingText = "Running nix fmt";
          output = "log";
        }
        {
          # Lazygit accepts control bindings only with lowercase letters.
          key = "<c-g>";
          context = "global";
          command = "mask generate";
          description = "Run mask generate";
          loadingText = "Running mask generate";
          output = "log";
        }
      ];
    };
  };

  home.activation.validateLazygitConfig = lib.mkIf platform.isLinux (mkLazyAppConfigValidation {
    arguments = [ "__home_manager_validate_config__" ];
    displayName = "Lazygit";
    expectedFailure = "Invalid git arg value: '__home_manager_validate_config__'";
    package = config.programs.lazygit.package;
    program = "lazygit";
    settings = config.programs.lazygit.settings;
  });

  programs.gitui.enable = false;
}
// lib.optionalAttrs platform.isLinux {
  catppuccin.lazygit.enable = true;
}
