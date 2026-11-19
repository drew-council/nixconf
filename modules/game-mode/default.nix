# Console-style Steam session: gamescope owns one output on its own VT while
# the desktop session stays logged in on another VT.
{
  flake.modules.nixos.game-mode =
    {
      config,
      lib,
      pkgs,
      utils,
      ...
    }:
    let
      inherit (config.my.host.display.gameMode) connector vkDevice;
      user = config.my.user.name;
      inherit (config.users.users.${user}) home;
      vt = 8;
      width = 3840;
      height = 2160;
      refresh = 120;
      unit = "game-mode.service";
      tty = "tty${toString vt}";
      steam = config.programs.steam.package;

      gamescopeArgs = [
        "--prefer-output"
        connector
        "--prefer-vk-device"
        vkDevice
        "--output-width"
        (toString width)
        "--output-height"
        (toString height)
        "--nested-width"
        (toString width)
        "--nested-height"
        (toString height)
        "--nested-refresh"
        (toString refresh)
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
          pkgs.coreutils
          pkgs.gamescope
          steam
        ];
        # Steam reads the display's native mode from the EDID gamescope writes.
        # Steam still caps external displays at 1080p unless Settings > Developer
        # > "Enable Native Resolution on External Displays" is on (stored as
        # EnableSteamNativeExternalResolution in Steam's config/config.vdf).
        text = ''
          state="''${XDG_CONFIG_HOME:-$HOME/.config}/gamescope"
          export GAMESCOPE_MODE_SAVE_FILE="$state/modes.cfg"
          export GAMESCOPE_PATCHED_EDID_FILE="$state/edid.bin"
          mkdir -p "$state"
          touch "$GAMESCOPE_MODE_SAVE_FILE" "$GAMESCOPE_PATCHED_EDID_FILE"

          exec gamescope ${lib.escapeShellArgs gamescopeArgs} -- steam -gamepadui -steamos3
        '';
      };

      # Shared by the root helpers below.
      sessionLib = ''
        # Sessions on the game VT. Normally one.
        game_sessions() {
          local id
          while read -r id _; do
            if [[ $(loginctl show-session "$id" --value --property=VTNr 2>/dev/null) == ${toString vt} ]]; then
              echo "$id"
            fi
          done < <(loginctl list-sessions --no-legend)
        }

        # Steam's helper processes outlive it, and gamescope waits for them
        # forever while ignoring SIGTERM. Nothing in the session has state left
        # to save once Steam is gone.
        end_game_sessions() {
          local signal id
          for signal in SIGTERM SIGKILL; do
            for id in $(game_sessions); do
              loginctl kill-session "$id" --signal="$signal" 2>/dev/null || true
            done
            for _ in $(seq 15); do
              [[ -n $(game_sessions) ]] || return 0
              sleep 0.2
            done
          done
        }

        # -steamos3 persists the steamdeck_stable client channel. Desktop Steam
        # would see it, switch channels back, and show a beta notice.
        forget_client_channel() {
          rm -f ${home}/.local/share/Steam/package/beta
        }

        # VT of the user's desktop session, else the greeter, else VT 1.
        desktop_vt() {
          local id key value target="" greeter=""
          local -A props
          while read -r id _; do
            props=()
            while IFS='=' read -r key value; do
              props[$key]=$value
            done < <(loginctl show-session "$id" -p Name -p Seat -p VTNr -p Type -p Class 2>/dev/null)

            local session_vt=''${props[VTNr]:-0}
            [[ ''${props[Seat]:-} == seat0 && $session_vt -gt 0 && $session_vt -ne ${toString vt} ]] || continue

            if [[ ''${props[Name]:-} == ${user} && ''${props[Class]:-} == user ]] &&
              [[ ''${props[Type]:-} == wayland || ''${props[Type]:-} == x11 ]]; then
              target=$session_vt
              break
            fi
            if [[ ''${props[Class]:-} == greeter ]]; then
              greeter=$session_vt
            fi
          done < <(loginctl list-sessions --no-legend)

          echo "''${target:-''${greeter:-1}}"
        }
      '';

      # Runs as root: as the session user it would inherit PAMName= and fail to
      # claim the VT the main process already holds. Steam MUST quit first so it
      # can save state.
      stopSession = pkgs.writeShellApplication {
        name = "game-mode-stop";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.kbd
          pkgs.procps
          pkgs.util-linux
          config.systemd.package
          steam
        ];
        text = ''
          ${sessionLib}
          if pgrep -u ${user} -x steam >/dev/null; then
            uid=$(id -u ${user})
            timeout 20 setpriv --reuid="$uid" --regid="$(id -g ${user})" --init-groups \
              env HOME=${home} USER=${user} LOGNAME=${user} \
              XDG_RUNTIME_DIR="/run/user/$uid" steam -shutdown || true
            for _ in $(seq 100); do
              pgrep -u ${user} -x steam >/dev/null || break
              sleep 0.2
            done
          fi

          # Back to the desktop before cleanup, so the console barely shows.
          chvt "$(desktop_vt)" || true
          end_game_sessions
          forget_client_channel
        '';
      };

      # Runs as root after every stop, including crashes and kills, so the
      # display is never left on a dead VT.
      returnVt = pkgs.writeShellApplication {
        name = "game-mode-return-vt";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.kbd
          config.systemd.package
        ];
        text = ''
          ${sessionLib}
          chvt "$(desktop_vt)" || true
          end_game_sessions
          forget_client_channel
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
      assertions = [
        {
          assertion = config.programs.steam.enable;
          message = "game-mode requires programs.steam.enable";
        }
        {
          assertion = builtins.elem "gaming" config.my.host.features;
          message = "game-mode requires the gaming feature";
        }
      ];

      environment.systemPackages = [ exitGameMode ];

      programs.steam.extraPackages = [ steamosShims ];

      # Game mode runs the steamdeck_stable client. Keep desktop Steam on the
      # same build so switching modes never reinstalls the client.
      programs.steam.package = pkgs.steam.override { extraArgs = "-clientbeta steamdeck_stable"; };

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
        description = "Steam game mode (gamescope on ${connector})";
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
          "/etc/profiles/per-user/${user}"
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
          User = user;
          PAMName = "game-mode";

          # Switch first so the session starts on the foreground VT and logind
          # marks it active immediately.
          ExecStartPre = "+${pkgs.kbd}/bin/chvt ${toString vt}";
          ExecStart = lib.getExe session;
          ExecStop = "+${lib.getExe stopSession}";
          ExecStopPost = "+${lib.getExe returnVt}";
          TimeoutStopSec = 60;
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
            subject.user == "${user}"
          ) {
            var verb = action.lookup("verb");
            if (verb == "start" || verb == "stop" || verb == "restart") {
              return polkit.Result.YES;
            }
          }
        });
      '';
    };

  flake.modules.homeManager.game-mode =
    { config, pkgs, ... }:
    let
      inherit (config.my.host) display;
      audioProfile = display.profiles.${display.gameModeProfile};

      configJson = pkgs.writeText "game-mode.json" (
        builtins.toJSON {
          inherit (display.gameMode) connector;
          audio = {
            alsaName = audioProfile.defaultAudioOutputAlsaName;
            cardName = audioProfile.audioCardName;
            cardProfile = audioProfile.audioCardProfile;
          };
        }
      );
    in
    {
      home.packages = [ (pkgs.game-mode.override { inherit configJson; }) ];
    };
}
