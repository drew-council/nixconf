{
  config,
  lib,
  pkgs,
  utils,
  vars,
  ...
}:

# Console-style Steam session: gamescope owns one output on its own VT while
# the desktop session stays logged in on another VT.
let
  cfg = config.gameMode;
  unit = "game-mode.service";
  tty = "tty${toString cfg.vt}";
  steam = config.programs.steam.package;

  gamescopeArgs = [
    "--prefer-output"
    cfg.connector
    "--prefer-vk-device"
    cfg.vkDevice
    "--output-width"
    (toString cfg.width)
    "--output-height"
    (toString cfg.height)
    "--nested-width"
    (toString cfg.width)
    "--nested-height"
    (toString cfg.height)
    "--nested-refresh"
    (toString cfg.refresh)
    "--adaptive-sync"
    "--hdr-enabled"
    "--xwayland-count"
    "2"
    "--hide-cursor-delay"
    "3000"
    "--fade-out-duration"
    "200"
    "--steam"
  ];

  session = pkgs.writeShellApplication {
    name = "game-mode-session";
    runtimeInputs = [
      pkgs.gamescope
      steam
    ];
    text = ''
      exec gamescope ${lib.escapeShellArgs gamescopeArgs} -- steam -gamepadui -steamos3
    '';
  };

  # Runs as the session user. Steam MUST quit before gamescope so it can save
  # state; gamescope then exits on its own when its child is gone.
  stopSession = pkgs.writeShellApplication {
    name = "game-mode-stop";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.procps
      steam
    ];
    text = ''
      if pgrep -u "$(id -u)" -x steam >/dev/null; then
        timeout 20 steam -shutdown || true
      fi
      for _ in $(seq 50); do
        kill -0 "''${MAINPID:-0}" 2>/dev/null || exit 0
        sleep 0.5
      done
    '';
  };

  # Runs as root after every stop, including crashes and kills, so the
  # display is never left on a dead VT.
  returnVt = pkgs.writeShellApplication {
    name = "game-mode-return-vt";
    runtimeInputs = [
      pkgs.gawk
      pkgs.kbd
      config.systemd.package
    ];
    text = ''
      target=""
      greeter=""
      while read -r id; do
        unset props
        declare -A props=()
        while IFS='=' read -r key value; do
          props[$key]=$value
        done < <(loginctl show-session "$id" -p Name -p Seat -p VTNr -p Type -p Class)

        vt=''${props[VTNr]:-0}
        [[ ''${props[Seat]:-} == seat0 && $vt -gt 0 && $vt -ne ${toString cfg.vt} ]] || continue

        if [[ ''${props[Name]:-} == ${cfg.user} && ''${props[Class]:-} == user ]] &&
          [[ ''${props[Type]:-} == wayland || ''${props[Type]:-} == x11 ]]; then
          target=$vt
          break
        fi
        if [[ ''${props[Class]:-} == greeter ]]; then
          greeter=$vt
        fi
      done < <(loginctl list-sessions --no-legend | awk '{ print $1 }')

      chvt "''${target:-''${greeter:-1}}"
    '';
  };

  exitGameMode = pkgs.writeShellApplication {
    name = "game-mode-exit";
    runtimeInputs = [ config.systemd.package ];
    text = ''
      exec systemctl stop --no-block ${unit}
    '';
  };

  # Steam's SteamOS UI (-steamos3) calls these. "Switch to Desktop" runs
  # holo-session-select (or the older steamos-session-select).
  sessionSelect = pkgs.writeShellScript "session-select" ''
    case "''${1:-gamescope}" in
      gamescope) ;;
      *) exec ${lib.getExe exitGameMode} ;;
    esac
  '';
  selectBranch = pkgs.writeShellScript "select-branch" ''
    case "''${1:-}" in
      -c | -l) echo main ;;
    esac
  '';
  # 7 means "no update available".
  noUpdate = pkgs.writeShellScript "no-update" "exit 7";
  noop = pkgs.writeShellScript "noop" "exit 0";
  steamosShims = pkgs.runCommand "game-mode-steamos-shims" { } ''
    install -D ${sessionSelect} $out/bin/holo-session-select
    install -D ${sessionSelect} $out/bin/steamos-session-select
    install -D ${selectBranch} $out/bin/steamos-select-branch
    install -D ${noUpdate} $out/bin/steamos-polkit-helpers/steamos-update
    install -D ${noop} $out/bin/steamos-polkit-helpers/jupiter-biosupdate
  '';
in
{
  options.gameMode = {
    enable = lib.mkEnableOption "the gamescope Steam game mode session";
    user = lib.mkOption {
      type = lib.types.str;
      default = vars.user;
      description = "User the session runs as.";
    };
    vt = lib.mkOption {
      type = lib.types.ints.between 1 63;
      default = 8;
      description = "Virtual terminal the session runs on.";
    };
    connector = lib.mkOption {
      type = lib.types.str;
      example = "HDMI-A-1";
      description = "DRM connector gamescope drives. All other outputs go dark.";
    };
    vkDevice = lib.mkOption {
      type = lib.types.str;
      example = "1002:744c";
      description = "Vulkan device (vendor:device) gamescope composites on.";
    };
    width = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3840;
    };
    height = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2160;
    };
    refresh = lib.mkOption {
      type = lib.types.ints.positive;
      default = 120;
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.programs.steam.enable;
        message = "gameMode requires programs.steam.enable";
      }
    ];

    environment.systemPackages = [ exitGameMode ];

    programs.steam.extraPackages = [ steamosShims ];

    # gamescope's WSI layer lets games present HDR. It only activates inside
    # gamescope (ENABLE_GAMESCOPE_WSI).
    hardware.graphics = {
      extraPackages = [ pkgs.gamescope-wsi ];
      extraPackages32 = [ pkgs.pkgsi686Linux.gamescope-wsi ];
    };

    # pam_systemd registers a full logind session on the VT. No kwallet or
    # other desktop login modules.
    security.pam.services.game-mode = {
      useDefaultRules = false;
      rules = {
        auth = utils.pam.autoOrderRules [
          {
            name = "unix";
            control = "required";
            modulePath = config.security.pam.pam_unixModulePath;
          }
        ];
        account = utils.pam.autoOrderRules [
          {
            name = "unix";
            control = "required";
            modulePath = config.security.pam.pam_unixModulePath;
          }
        ];
        session = utils.pam.autoOrderRules [
          {
            name = "unix";
            control = "required";
            modulePath = config.security.pam.pam_unixModulePath;
          }
          {
            name = "env";
            control = "required";
            modulePath = "${config.security.pam.package}/lib/security/pam_env.so";
            settings.conffile = "/etc/pam/environment";
            settings.readenv = 0;
          }
          {
            name = "systemd";
            control = "required";
            modulePath = "${config.systemd.package}/lib/security/pam_systemd.so";
          }
        ];
      };
    };

    systemd.services.game-mode = {
      description = "Steam game mode (gamescope on ${cfg.connector})";
      after = [
        "systemd-user-sessions.service"
        "systemd-logind.service"
      ];
      conflicts = [
        "getty@${tty}.service"
        "autovt@${tty}.service"
      ];
      # A rebuild MUST NOT kill a running game.
      restartIfChanged = false;
      # The same PATH a login shell gets, for Steam and the games it starts.
      path = [
        "/run/wrappers"
        "/etc/profiles/per-user/${cfg.user}"
        "/run/current-system/sw"
      ];
      unitConfig.ConditionPathExists = "/dev/${tty}";

      environment = {
        XDG_SESSION_TYPE = "wayland";
        XDG_SESSION_CLASS = "user";
        XDG_SESSION_DESKTOP = "gamescope";
        XDG_CURRENT_DESKTOP = "gamescope";

        # Subset of SteamOS's gamescope-session environment.
        ENABLE_GAMESCOPE_WSI = "1";
        SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS = "0";
        STEAM_DISABLE_AUDIO_DEVICE_SWITCHING = "1";
        STEAM_GAMESCOPE_COLOR_MANAGED = "1";
        STEAM_GAMESCOPE_FANCY_SCALING_SUPPORT = "1";
        STEAM_GAMESCOPE_HAS_TEARING_SUPPORT = "1";
        STEAM_GAMESCOPE_HDR_SUPPORTED = "1";
        STEAM_GAMESCOPE_NIS_SUPPORTED = "1";
        STEAM_GAMESCOPE_TEARING_SUPPORTED = "1";
        STEAM_GAMESCOPE_VIRTUAL_WHITE = "1";
        STEAM_GAMESCOPE_VRR_SUPPORTED = "1";
        STEAM_MULTIPLE_XWAYLANDS = "1";
        vk_xwayland_wait_ready = "false";
      };

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        PAMName = "game-mode";

        # Switch first so the session starts on the foreground VT and logind
        # marks it active immediately.
        ExecStartPre = "+${pkgs.kbd}/bin/chvt ${toString cfg.vt}";
        ExecStart = lib.getExe session;
        ExecStop = lib.getExe stopSession;
        ExecStopPost = "+${lib.getExe returnVt}";
        TimeoutStopSec = 40;
        Restart = "no";

        UtmpIdentifier = tty;
        UtmpMode = "user";
        TTYPath = "/dev/${tty}";
        TTYReset = true;
        TTYVHangup = true;
        TTYVTDisallocate = true;
        StandardInput = "tty-fail";
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    security.polkit.extraConfig = ''
      // game-mode: let the session user start and stop only this unit.
      polkit.addRule(function(action, subject) {
        if (
          action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "${unit}" &&
          subject.user == "${cfg.user}"
        ) {
          var verb = action.lookup("verb");
          if (verb == "start" || verb == "stop" || verb == "restart") {
            return polkit.Result.YES;
          }
        }
      });
    '';
  };
}
