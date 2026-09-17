{
  config,
  lib,
  pkgs,
  platform,
  ...
}:
let
  # macOS runs the upstream Homebrew cask: the nixpkgs voxtype is Linux-only
  # (alsa/wtype/dotool deps, meta.platforms = linux).
  voxtypeBin = if platform.isLinux then lib.getExe pkgs.voxtype else "/opt/homebrew/bin/voxtype";

  # Keep the cached nixpkgs binary unchanged; only wrap credential loading.
  voxtype = pkgs.writeShellApplication {
    name = "voxtype";
    runtimeInputs = lib.optionals platform.isLinux [
      pkgs.wtype
      pkgs.wl-clipboard
    ];
    text = ''
      # Read opnix's raw credential at runtime, never into the Nix store.
      # Control commands must still work if the credential is unavailable.
      case "''${1:-daemon}" in
        record|status|config|--help|--version) ;;
        *)
          key_file=${lib.escapeShellArg config.programs.onepassword-secrets.secretPaths.voxtypeOpenai}
          if [[ ! -r "$key_file" ]]; then
            echo "Voxtype: missing $key_file; activate Home Manager with opnix configured." >&2
            exit 1
          fi
          VOXTYPE_WHISPER_API_KEY=$(< "$key_file")
          if [[ ! "$VOXTYPE_WHISPER_API_KEY" =~ [^[:space:]] ]]; then
            echo "Voxtype: OpenAI credential is empty." >&2
            exit 1
          fi
          export VOXTYPE_WHISPER_API_KEY
          ;;
      esac
      ${lib.optionalString platform.isLinux ''
        export SSL_CERT_FILE="''${SSL_CERT_FILE:-${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt}"
      ''}
      exec ${voxtypeBin} "$@"
    '';
  };

  # Settings shared by both platforms.
  sharedSettings = {
    state_file = "auto";
    audio.max_duration_secs = 120;
    # Deliberately no loadModels: remote-only, no model downloads or local inference.
    whisper = {
      mode = "remote";
      # Both nixpkgs 0.6.6 and the cask 0.7.5 append /v1/audio/transcriptions to
      # the endpoint unconditionally (0.7.5's TUI help text misleadingly shows
      # "https://api.openai.com/v1"; its own unit tests append the path).
      remote_endpoint = "https://api.openai.com";
      remote_timeout_secs = 120;
      language = "auto";
      translate = false;
      # Sent to the remote backend. The daemon's ModelManager overrides
      # remote_model with this field, so both must be set for the daemon and
      # the `voxtype transcribe` subcommand to agree on the model.
      model = "gpt-transcribe";
      remote_model = "gpt-transcribe";
    };
    output = {
      mode = "type";
      auto_submit = false;
      notification = {
        on_recording_start = true;
        on_recording_stop = true;
        on_transcription = false;
      };
    };
  };

  # The Homebrew cask ships 0.7.5, where [hotkey], [audio], and [output] are
  # required tables (no serde defaults), [audio] must carry device/sample_rate,
  # and driver_order must be omitted (None -> platform default chain).
  darwinSettings = sharedSettings // {
    audio = {
      device = "default";
      sample_rate = 16000;
      inherit (sharedSettings.audio) max_duration_secs;
    };
    hotkey = {
      enabled = true; # No compositor bindings on macOS; use the global hotkey.
      # Push-to-talk on right Option (Discord style). NOTE: voxtype's macOS
      # hotkey backend matches single keys only -- modifiers in config are
      # ignored there, so combos like Cmd+R are impossible (and a bare letter
      # would fire on every keystroke).
      key = "RIGHTALT";
    };
    whisper = sharedSettings.whisper;
    output = sharedSettings.output // {
      # No driver_order: macOS types natively via the Quartz event tap.
      notification = sharedSettings.output.notification;
    };
    osd.enabled = false; # voxtype-osd is not shipped in the cask.
  };
in
{
  # NOTE: keep this module a single attrset with mkIf guards. Splitting
  # platform-specific definitions into `// lib.optionalAttrs` attrsets is a
  # trap: `//` is a shallow merge, so a block defining `home.packages` clobbers
  # every other `home.*` definition (home.file, sessionVariables, ...).

  programs.onepassword-secrets = {
    # op.nix owns the shared enable + tokenFile on Linux; stand the module up
    # for darwin here so only the voxtype secret is declared on the Mac.
    enable = lib.mkDefault true;
    tokenFile = lib.mkDefault "/etc/opnix-token";

    secrets.voxtypeOpenai = {
      reference = "op://opnix/openai-personal/credential";
      path = "${config.xdg.configHome}/voxtype/openai-api-key";
      mode = "0600";
    };
  };

  # Linux gets its config from the HM systemd service module
  # (services.voxtype.settings). On darwin the cask reads the config from the
  # macOS Application Support path, not ~/.config/voxtype/.
  home.file."Library/Application Support/voxtype/config.toml" = lib.mkIf platform.isDarwin {
    source = (pkgs.formats.toml { }).generate "voxtype-config.toml" darwinSettings;
  };

  services.voxtype = lib.mkIf platform.isLinux {
    enable = true;
    package = voxtype;
    # Give the daemon's output drivers (wtype, wl-copy) access to the session.
    wayland.display = "wayland-1";
    settings = sharedSettings // {
      hotkey.enabled = false; # Hyprland bindings; no evdev/input-group access.
      output = sharedSettings.output // {
        driver_order = [
          "wtype"
          "clipboard"
        ];
      };
    };
  };

  # launchd agent replaces the HM systemd user service, which is Linux-only.
  launchd.agents.voxtype = lib.mkIf platform.isDarwin {
    enable = true;
    # ProgramArguments only: HM's waitForNixStore wrapper concatenates Program
    # into the argument list, which would duplicate the binary path.
    config = {
      ProgramArguments = [
        "${voxtype}/bin/voxtype"
        "daemon"
      ];
      RunAtLoad = true;
      KeepAlive = true; # Always restart; daemon exits 0 on SIGTERM during rebuilds.
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/voxtype/stdout.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/voxtype/stderr.log";
    };
  };

  home.packages = lib.optionals platform.isDarwin [ voxtype ];

  # launchd does not create parent directories for the log paths above.
  home.activation.createVoxtypeLogDir = lib.mkIf platform.isDarwin (
    lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      mkdir -p "${config.home.homeDirectory}/Library/Logs/voxtype"
    ''
  );
}
