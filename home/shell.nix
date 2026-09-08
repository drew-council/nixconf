{
  lib,
  pkgs,
  vars,
  ...
}:
let
  mySessionVariables = {
    EDITOR = vars.defaults.termEditor;
    # VISUAL = vars.defaults.editor;
    BROWSER = vars.defaults.browser;
    NH_FLAKE = vars.flakePath;
    NH_NO_CHECKS = 1;
    NIXPKGS_ALLOW_UNFREE = 1;
    PAGER = "bat";
  };
  myShellAliases = {
    cdn = "cd ${vars.flakePath}";
    e = "${vars.defaults.editor} .";
    cx = "codex";

    ld = "lazydocker";
    hmclean = "fd '${vars.hmBackupFileExtension}' ~ -u -x rm";
    dcd = "docker compose down";
    cg = "cargo";
  }
  // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
    zed = "zeditor";
  };

  # `atuin init nu` names both its ctrl-r and up-arrow keybindings "atuin",
  # which recent nushell warns about on every startup.
  atuinUpBinding = "name: atuin\n            modifier: none";
  atuinNushellConfig =
    pkgs.runCommand "atuin-nushell-config.nu"
      {
        nativeBuildInputs = [ pkgs.writableTmpDirAsHomeHook ];
      }
      ''
        ${lib.getExe pkgs.atuin} init nu >> "$out"
        substituteInPlace $out \
          --replace-fail ${lib.escapeShellArg atuinUpBinding} ${
            lib.escapeShellArg (lib.replaceStrings [ "name: atuin" ] [ "name: atuin_up" ] atuinUpBinding)
          }
      '';
in
{
  home = {
    shellAliases = myShellAliases;
    sessionVariables = mySessionVariables;
    sessionPath = [
      "${vars.home}/.local/bin"
    ];
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
        nuscripts = pkgs.fetchFromGitHub {
          owner = "nushell";
          repo = "nu_scripts";
          rev = "ec945380be3981522f9bb55e764a5254a908e652";
          hash = "sha256-0fw0fJSlUnT5vbBHDubqLrk3F+OU7CE15vIeU295C4w=";
        };

        cargoCompletions = pkgs.runCommand "cargo-completions.nu" { } ''
          cp ${nuscripts}/custom-completions/cargo/cargo-completions.nu $out
          substituteInPlace $out \
            --replace-fail \
              "\$metadata | from json | get workspace_members | split column ' ' | get column1" \
              "let parsed_metadata = (\$metadata | from json); \$parsed_metadata.packages | where id in \$parsed_metadata.workspace_members | get name"
        '';

        completionPath =
          input:
          if input == "cargo" then
            cargoCompletions
          else
            "${nuscripts}/custom-completions/${input}/${input}-completions.nu";
        formatInput = input: "source ${completionPath input}";
        formatCompletions = inputs: (builtins.concatStringsSep "\n" (map formatInput inputs)) + "\n";
      in
      {
        enable = true;
        plugins = with pkgs.nushellPlugins; [
          # dbus # interact with dbus, broken
          formats # additional file formats
          gstat # git status for repo
          # hcl # load hashicorp config lang files, incompatible version
          # highlight # highlight source code
          # net # list network interfaces, broken
          # polars # dataframe operations, broken with Rust 1.97
          query # query sql, json, etc
          # skim # integrates `sk` fuzzy finder
          # units # easily convert between common units, incompatible version

          # pkgs.nu-plugin-toon # custom plugin for TOON support
        ];
        shellAliases = myShellAliases;
        environmentVariables = mySessionVariables // {
          PROMPT_INDICATOR_VI_INSERT = "";
        };
        settings = {
          show_banner = false; # don't show startup help text
          buffer_editor = vars.defaults.termEditor;
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
            # nix-darwin's environment.systemPath only reaches PATH via
            # /etc/zshenv, which nushell never sources.
            $env.PATH = ($env.PATH | append ["/opt/homebrew/bin" "/opt/homebrew/sbin"] | uniq)
            # herdr exports SHELL=<default_shell> (nu) into panes like tmux's
            # default-shell; restore the macOS login shell for child processes.
            $env.SHELL = "/bin/zsh"
          ''
          + ''

            source ${./utils.nu};
            use ${nuscripts}/modules/jc/
            source ${atuinNushellConfig}

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
      # sourced manually below to deduplicate keybinding names
      enableNushellIntegration = false;
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
}
