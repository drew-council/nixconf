{
  flake.modules.nixos.desktop-linux =
    { pkgs, ... }:
    {
      programs.hyprland = {
        enable = true;
        package = pkgs.hyprland;
        portalPackage = pkgs.xdg-desktop-portal-hyprland;
      };

      environment.sessionVariables = {
        NIXOS_OZONE_WL = "1";
        MOZ_ENABLE_WAYLAND = "1";
      };

      environment.systemPackages = with pkgs; [
        hyprpicker # color picker
        hyprshot # screenshots
        hyprpaper # wallpaper daemon

        playerctl # media key control
        brightnessctl # backlight control
        udiskie # removable drive automounter
        networkmanagerapplet # network tray applet
        blueman # bluetooth manager
        pavucontrol # audio mixer
        swaynotificationcenter # notification center
        libnotify # send desktop notifications
        hyprpolkitagent # polkit authentication prompts
        wl-clipboard # clipboard CLI
        wtype # simulate keyboard input
        bemoji # emoji picker
        wev # show input events
        cliphist # clipboard history
      ];
    };

  flake.modules.homeManager.desktop-linux =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.my.host) display;

      tabletHeadless = {
        name = "HEADLESS-TABLET";
        width = 2560;
        height = 1600;
        downsample = 2;
        scale = 1.0;
        position = "auto-left";
      };

      monitorLayoutPoke = pkgs.writeShellApplication {
        name = "hypr-monitor-layout-poke";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.fuzzel
          pkgs.gnugrep
          pkgs.hyprland
        ];
        text = builtins.readFile ./poke-layer-layout.sh;
      };

      profileLabels = [
        "default"
      ]
      ++ lib.sort lib.lessThan (lib.attrNames (display.profiles or { }));
      profilesJson = pkgs.writeText "hypr-monitor-profiles.json" (
        builtins.toJSON {
          profiles = map (label: {
            inherit label;
            useTablet = ((display.profiles or { }).${label} or { }).useTablet or false;
          }) profileLabels;
          tabletHeadlessName = tabletHeadless.name;
        }
      );

      hyprlandPortalPackage = pkgs.xdg-desktop-portal-hyprland;
      toLua = lib.generators.toLua { };

      generatedLua = {
        gaming = builtins.elem "gaming" config.my.host.features;
        gameMode = builtins.elem "game-mode" config.my.host.features;
        defaults = {
          browser = "zen-beta";
          calculator = "qalculate-qt";
          editor = "zeditor --new";
          fileManager = "dolphin";
          tty = "ghostty";
          inherit (config.my.user) home;
        };
        commands = {
          kwalletInit = "${pkgs.kdePackages.kwallet-pam}/libexec/pam_kwallet_init";
          monitorLayoutPoke = lib.getExe monitorLayoutPoke;
          monitorProfileSelector = "hypr-monitor-profile";
          switchaudio = lib.getExe pkgs.switchaudio;
          voxtype = lib.getExe config.services.voxtype.package;
        };
        catppuccin = {
          mauve = "rgba(cba6f7ff)";
          pink = "rgba(f5c2e7ff)";
          accent = "mauve";
        };
        monitor = {
          host = display;
          inherit tabletHeadless;
        };
      };

      # lua module files in require order
      luaModules = [
        "core"
        "util"
        "animations"
        "autostart"
        "monitor_profiles"
        "binds"
      ];

      luaModuleRequires = map (module: "nixconf.${module}") luaModules;

      luaModuleConfigFiles = lib.listToAttrs (
        map (module: {
          name = "hypr/nixconf/${module}.lua";
          value.source = ./src + "/${module}.lua";
        }) luaModules
      );

      luaModuleClearLines = lib.concatMapStringsSep "\n" (module: ''package.loaded["${module}"] = nil'') (
        [ "nixconf.generated" ] ++ luaModuleRequires
      );
      luaModuleRequireLines = lib.concatMapStringsSep "\n" (
        module: ''require("${module}")''
      ) luaModuleRequires;
    in
    {
      home.packages = [
        (pkgs.hypr-monitor-profile.override { inherit profilesJson; })
        pkgs.kitty-hypr-nav
        pkgs.monitors
        pkgs.switchaudio
        pkgs.tabletdisplay
      ];

      # Distinguish automation windows from ordinary Chrome/Chromium windows.
      home.file.".agent-browser/config.json".text = builtins.toJSON {
        args = "--class=agent-browser";
      };

      catppuccin.hyprland = {
        enable = false;
        accent = "mauve";
      };

      xdg.portal = {
        enable = true;
        extraPortals = [
          pkgs.kdePackages.xdg-desktop-portal-kde
          pkgs.xdg-desktop-portal-gtk
        ];
        config.hyprland = {
          default = [
            "hyprland"
            "gtk"
            "kde"
          ];
          "org.freedesktop.impl.portal.FileChooser" = [ "kde" ];
          "org.freedesktop.impl.portal.Settings" = [ "gtk" ];
          "org.freedesktop.impl.portal.ScreenCast" = [ "hyprland" ];
          "org.freedesktop.impl.portal.Screenshot" = [ "hyprland" ];
        };
      };

      wayland.windowManager.hyprland = {
        enable = true;
        # NixOS installs the compositor; Home Manager only manages its config.
        package = null;
        portalPackage = hyprlandPortalPackage;
        systemd.enable = false;
        configType = "lua";
        xwayland = {
          enable = true;
        };
        settings = { };
        extraConfig = # lua
          ''
            local config_home = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
            package.path = config_home .. "/hypr/?.lua;" .. config_home .. "/hypr/?/init.lua;" .. package.path

            ${luaModuleClearLines}

            ${luaModuleRequireLines}
          '';
      };

      xdg.configFile = {
        "hypr/nixconf/generated.lua".text = # lua
          ''
            return ${toLua generatedLua}
          '';
      }
      // luaModuleConfigFiles;

      systemd.user.targets.hyprland-session = {
        Unit = {
          Description = "Hyprland compositor session";
          Documentation = [ "man:systemd.special(7)" ];
          BindsTo = [ "graphical-session.target" ];
          Wants = [ "graphical-session-pre.target" ];
          After = [ "graphical-session-pre.target" ];
        };
      };
    };
}
