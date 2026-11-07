{
  flake.modules.homeManager.terminal =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      json = pkgs.formats.json { };
      toml = pkgs.formats.toml { };
      keybindsPlugin = pkgs.herdr-keybinds.override {
        workspaceRoots = [
          "personal"
          (baseNameOf config.my.user.workDir)
        ];
        sheerRepo = "${config.my.user.workDir}/sheer";
        gh = config.programs.gh.package;
      };
      pluginId = "drew.herdr-keybinds";
      pluginDir = "herdr/plugins/${pluginId}";
      actionContexts = [
        "pane"
        "tab"
        "workspace"
      ];
      keybindsCommand =
        subcommand: args:
        [
          (lib.getExe keybindsPlugin)
          subcommand
        ]
        ++ args;
      actionCommand = subcommand: arg: keybindsCommand subcommand [ arg ];
      # Plugin panes are spawned by the herdr server, so they inherit its
      # environment instead of the login environment interactive panes get.
      loginShellCommand = command: [
        "${pkgs.zsh}/bin/zsh"
        "-l"
        "-c"
        "exec ${lib.escapeShellArgs command}"
      ];
      # Add popup applications here. Each entry gets its toggle action, keybinding,
      # and overlay pane automatically.
      popupApps = [
        {
          id = "lazygit";
          key = "alt+g";
          title = "Toggle lazygit overlay";
          package = pkgs.lazygit;
        }
        {
          id = "btop";
          key = "alt+b";
          title = "Toggle btop overlay";
          package = pkgs.btop;
        }
      ];
      popupActions = map (popup: {
        id = "toggle-${popup.id}";
        inherit (popup) key title;
        command = keybindsCommand "toggle-popup" [ popup.id ];
      }) popupApps;
      keybindActions = [
        {
          id = "navigate-left";
          keys = [
            "alt+h"
            "alt+left"
          ];
          title = "Navigate left";
          command = actionCommand "navigate" "left";
        }
        {
          id = "navigate-down";
          keys = [
            "alt+j"
            "alt+down"
          ];
          title = "Navigate down";
          command = actionCommand "navigate" "down";
        }
        {
          id = "navigate-up";
          keys = [
            "alt+k"
            "alt+up"
          ];
          title = "Navigate up";
          command = actionCommand "navigate" "up";
        }
        {
          id = "navigate-right";
          keys = [
            "alt+l"
            "alt+right"
          ];
          title = "Navigate right";
          command = actionCommand "navigate" "right";
        }
      ]
      ++ popupActions
      ++ [
        {
          id = "open-workspace";
          key = "alt+n";
          title = "Open workspace from directory picker";
          command = keybindsCommand "open-workspace-popup" [ ];
        }
        {
          id = "open-sheer-workspace";
          key = "alt+s";
          title = "Open or create sheer worktree";
          command = keybindsCommand "sheer-workspace-popup" [ ];
        }
        {
          id = "open-ghst";
          key = "alt+semicolon";
          title = "Open ghst in a right pane";
          command = keybindsCommand "open-ghst" [ ];
        }
      ];
      keybindPluginActions = map (action: {
        inherit (action) id title command;
        contexts = actionContexts;
      }) keybindActions;
      keybindCommandBindings = lib.concatMap (
        action:
        map (key: {
          inherit key;
          type = "plugin_action";
          command = "${pluginId}.${action.id}";
        }) (action.keys or [ action.key ])
      ) keybindActions;
      herdrConfig = {
        onboarding = false;

        theme = {
          name = "catppuccin";
          # Mocha mauve instead of the theme's default blue.
          custom.accent = "#cba6f7";
        };

        terminal = {
          default_shell = "nu";
          shell_mode = "auto";
          new_cwd = "follow";
        };

        update = {
          version_check = false;
          manifest_check = true;
        };

        keys = {
          prefix = "ctrl+b";
          workspace_picker = [
            "prefix+w"
            "alt+w"
          ];
          next_agent = "alt+a";
          new_tab = [
            "prefix+c"
            "alt+t"
          ];
          next_tab = "";
          close_tab = [
            "prefix+shift+x"
            "alt+q"
          ];
          split_vertical = [
            "prefix+v"
            "alt+v"
          ];
          split_horizontal = [
            "prefix+minus"
            "alt+minus"
          ];
          close_pane = [
            "prefix+x"
            "alt+x"
          ];
          command = keybindCommandBindings;
        };

        ui = {
          mouse_capture = true;
          prompt_new_tab_name = false;
          toast.delivery = "herdr";
          sound.enabled = false;
        };

        experimental = {
          allow_nested = false;
          kitty_graphics = true;
          pane_history = false;
        };
      };
      manifestData = {
        id = pluginId;
        name = "Drew Herdr Keybinds";
        version = "0.1.0";
        min_herdr_version = "0.7.0";
        description = "Directional pane, tab, and workspace navigation for Herdr.";
        platforms = [
          "linux"
          "macos"
        ];

        actions = keybindPluginActions;

        panes =
          map (popup: {
            inherit (popup) id;
            title = popup.id;
            placement = "overlay";
            command = loginShellCommand [ (lib.getExe popup.package) ];
          }) popupApps
          ++ [
            {
              id = "new-workspace-picker";
              title = "New workspace picker";
              placement = "overlay";
              command = loginShellCommand [
                (lib.getExe keybindsPlugin)
                "open-workspace"
                (lib.getExe pkgs.fzf)
              ];
            }
            {
              id = "sheer-workspace-picker";
              title = "Open or create sheer worktree";
              placement = "overlay";
              command = loginShellCommand [
                (lib.getExe keybindsPlugin)
                "sheer-workspace"
                (lib.getExe pkgs.fzf)
              ];
            }
          ];
      };
      manifest = toml.generate "herdr-keybinds-plugin.toml" manifestData;
      pluginRegistryFile = json.generate "herdr-plugins.json" pluginRegistry;
      pluginRegistry = [
        {
          inherit (manifestData)
            name
            version
            min_herdr_version
            description
            platforms
            actions
            panes
            ;
          plugin_id = pluginId;
          manifest_path = toString manifest;
          plugin_root = builtins.dirOf (toString manifest);
          enabled = true;
          source = {
            kind = "local";
          };
        }
      ];
    in
    {
      home.packages = [ keybindsPlugin ];

      # The sheer workspace action reads gh stack's catalog and runs gh stack in
      # new workspace panes, which only works when gh has the extension installed.
      assertions = [
        {
          assertion =
            config.programs.gh.enable
            && lib.any (extension: lib.getName extension == "gh-stack") config.programs.gh.extensions;
          message = "herdr's sheer workspace action needs programs.gh with the gh-stack extension";
        }
      ];

      xdg.configFile."herdr/config.toml".source = toml.generate "herdr-config.toml" herdrConfig;
      xdg.configFile."${pluginDir}/herdr-plugin.toml".source = manifest;

      # Register before installPackages: a failed package profile activation must not
      # leave Herdr's plugin unavailable when the generated config is already linked.
      home.activation.herdrPluginRegistry =
        lib.hm.dag.entryBetween [ "linkGeneration" ] [ "installPackages" ]
          ''
            run mkdir -p "$HOME/.config/herdr"
            run cp ${lib.escapeShellArg pluginRegistryFile} "$HOME/.config/herdr/plugins.json"
            run chmod 0644 "$HOME/.config/herdr/plugins.json"

            # Notify a running Herdr server, but do not fail activation when it is not
            # running (its stale socket makes the CLI return connection refused).
            if ! run ${lib.escapeShellArg (lib.getExe pkgs.herdr)} plugin link ${lib.escapeShellArg (toString manifest)}; then
              verboseEcho "Herdr is not running; it will load the generated plugin registry on next start"
            fi
          '';
    };
}
