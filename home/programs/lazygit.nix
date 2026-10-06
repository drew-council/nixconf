{
  config,
  inputs,
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
  # lazygit >= 0.60 deprecates `gui.authorColors` in favor of
  # `gui.theme.authorColors` and aborts at startup when its automatic config
  # migration cannot write the change back to the read-only /nix/store theme
  # file that the catppuccin module points LG_CONFIG_FILE at.
  # Pre-migrate the theme files so lazygit never sees the deprecated key.
  # Upstream: https://github.com/jesseduffield/lazygit/issues/4595
  catppuccin.sources.lazygit = inputs.catppuccin.packages.${pkgs.system}.lazygit.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      find "$out" -name '*.yml' -print0 | while IFS= read -r -d "" f; do
        awk '
          /^  authorColors:/ { print "    authorColors:"; moved = 1; next }
          moved && /^    / { sub(/^    /, "      "); print; next }
          moved && /^[[:space:]]*$/ { next }
          { moved = 0; print }
        ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
      done
    '';
  });

  catppuccin.lazygit.enable = true;
}
