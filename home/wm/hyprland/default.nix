{
  config,
  lib,
  pkgs,
  osConfig,
  vars,
  ...
}:
let
  switchaudio = import ../switchaudio/package.nix { inherit pkgs; };
  monitorConfig = import ./monitor-config.nix;
  monitorLayoutPoke = pkgs.writeShellApplication {
    name = "hypr-monitor-layout-poke";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.fuzzel
      pkgs.gnugrep
      pkgs.hyprland
    ];
    text = builtins.readFile ./monitor-switcher/poke-layer-layout.sh;
  };
  hyprlandPackage = pkgs.hyprland;
  hyprlandPortalPackage = pkgs.xdg-desktop-portal-hyprland;
  toLua = lib.generators.toLua { };

  generatedLua = {
    host = osConfig.networking.hostName;
    laptop = osConfig.laptop.enable;
    nvidia = osConfig.nvidiaEnable;
    personal = vars.isPersonal osConfig;
    defaults = {
      inherit (vars.defaults)
        browser
        calculator
        editor
        fileManager
        tty
        ;
      inherit (vars) home;
    };
    commands = {
      kwalletInit = "${pkgs.kdePackages.kwallet-pam}/libexec/pam_kwallet_init";
      monitorLayoutPoke = lib.getExe monitorLayoutPoke;
      monitorProfileSelector = "hypr-monitor-profile";
      switchaudio = lib.getExe switchaudio;
      voxtype = lib.getExe config.services.voxtype.package;
    };
    catppuccin = {
      mauve = "rgba(cba6f7ff)";
      pink = "rgba(f5c2e7ff)";
      accent = "mauve";
    };
    monitor = monitorConfig;
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
  imports = [ ./monitor-switcher ];

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
  };

  systemd.user.services.sunshine-tablet = {
    Unit = {
      Description = "Sunshine tablet stream";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
      Conflicts = [ "sunshine.service" ];
    };
    Service = {
      ExecStart = "${lib.getExe pkgs.sunshine} capture=wlr output_name=${monitorConfig.tabletHeadless.name}";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # Write portal config file
  home.file.".config/xdg-desktop-portal/hyprland-portals.conf".text = ''
    [preferred]
    default = hyprland;gtk;kde
    org.freedesktop.impl.portal.FileChooser = kde
    org.freedesktop.impl.portal.Settings = gtk
    org.freedesktop.impl.portal.ScreenCast = hyprland
    org.freedesktop.impl.portal.Screenshot = hyprland
  '';

  wayland.windowManager.hyprland = {
    enable = true;
    package = hyprlandPackage;
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
}
