{ config, ... }:
let
  inherit (config.my) liveLink;
in
{
  flake.modules.homeManager.terminal =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      mySessionVariables = {
        EDITOR = "nvim";
        NH_FLAKE = config.my.user.flakePath;
        NH_NO_CHECKS = 1;
        NIXPKGS_ALLOW_UNFREE = 1;
        PAGER = "bat";
      };
      myShellAliases = {
        cdn = "cd ${config.my.user.flakePath}";
        cx = "codex";

        gl = "lg";
        ld = "lazydocker";
        hmclean = "fd '${config.my.user.backupFileExtension}' ~ -u -x rm";
        dcd = "docker compose down";
        cg = "cargo";
      };
    in
    {
      home = {
        shellAliases = myShellAliases;
        sessionVariables = mySessionVariables;
        sessionPath = [
          "${config.my.user.home}/.local/bin"
        ];
        # configDir, because Nushell's default differs on macOS
        file."${config.programs.nushell.configDir}/autoload/utils.nu".source = liveLink config ./utils.nu;
      };

      programs = {
        zsh = {
          enable = true;
          syntaxHighlighting.enable = true;
          autosuggestion.enable = true;
        };

        bash = {
          enable = true;
          enableCompletion = false;
        };

        nushell =
          let
            nuscripts = "${pkgs.nu_scripts}/share/nu_scripts";
            completionPath = input: "${nuscripts}/custom-completions/${input}/${input}-completions.nu";
            formatInput = input: "source ${completionPath input}";
            formatCompletions = inputs: (builtins.concatStringsSep "\n" (map formatInput inputs)) + "\n";
          in
          {
            enable = true;
            loadSessionVariables = true;
            plugins = with pkgs.nushellPlugins; [
              formats # additional file formats
              gstat # git status for repo
              polars # dataframe operations
              query # query sql, json, etc
            ];
            # Home Manager feeds home.shellAliases to zsh and bash only.
            shellAliases = config.home.shellAliases;
            environmentVariables = mySessionVariables // {
              PROMPT_INDICATOR_VI_INSERT = "";
            };
            settings = {
              show_banner = false; # don't show startup help text
              buffer_editor = "nvim";
              edit_mode = "vi"; # vi line edit mode
            };
            extraConfig =
              formatCompletions [
                "cargo"
                "curl"
                "less"
                "make"
                "man"
                "op"
                "tar"
              ]
              + lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
                # herdr exports SHELL=<default_shell> (nu) into panes like tmux's
                # default-shell; restore the macOS login shell for child processes.
                $env.SHELL = "/bin/zsh"
              ''
              + ''

                use ${nuscripts}/modules/jc/

                nerdfetch
              '';
          };

        direnv = {
          enable = true;
          nix-direnv.enable = true;

          enableBashIntegration = false;
          enableZshIntegration = true;
          enableNushellIntegration = true;
        };

        eza = {
          enable = true;
          icons = "auto";
          enableNushellIntegration = false;
          enableZshIntegration = true;
          enableBashIntegration = false;
        };

        atuin = {
          enable = true;
          enableZshIntegration = true;
          enableNushellIntegration = true;
          enableBashIntegration = false;
          settings = {
            auto_sync = true;
            enter_accept = true;
            style = "compact";
            inline_height = 20;
            filter_mode_shell_up_key_binding = "session";
          };
        };

        yazi = {
          enable = true;
          enableZshIntegration = true;
          enableFishIntegration = true;
          enableNushellIntegration = true;
          enableBashIntegration = false;

          shellWrapperName = "y";
        };

        fzf = {
          enable = true;
          enableZshIntegration = false;
          enableFishIntegration = false;
          enableBashIntegration = false;
          enableNushellIntegration = false;
        };

        starship = {
          enable = true;
          enableZshIntegration = true;
          enableFishIntegration = true;
          enableNushellIntegration = true;
          enableBashIntegration = false;
          settings = {
            aws.disabled = true;
            gcloud.disabled = true;
            git_status.disabled = true;
            golang.disabled = true;
            nodejs.disabled = true;
            cmake.disabled = true;
            buf.disabled = true;
            python.disabled = true;
            character = {
              success_symbol = "[➜](bold green)";
              error_symbol = "[➜](bold red)";
            };
            # configure shell-specific icons
            shell = {
              disabled = false;
              format = "$indicator($style)";
              bash_indicator = "bash ";
              zsh_indicator = "%";
              nu_indicator = "";
              unknown_indicator = "? ";
              style = "white bold";
            };
          };
        };

        zellij = {
          enable = true;

          enableZshIntegration = false;
          enableFishIntegration = false;
          enableBashIntegration = false;
        };

        zoxide = {
          enable = true;
          enableZshIntegration = true;
          enableNushellIntegration = true;
          enableBashIntegration = false;
          options = [ "--cmd z" ];
        };
      };
    };
}
