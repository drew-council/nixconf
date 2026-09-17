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
in
{
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

  # Linux normally gets this file from the HM systemd service module
  # (services.voxtype.settings), which does not exist on darwin.
  xdg.configFile."voxtype/config.toml" = lib.mkIf platform.isDarwin {
    source = (pkgs.formats.toml { }).generate "voxtype-config.toml" (
      sharedSettings
      // {
        # No compositor bindings on macOS; use the built-in global hotkey.
        # Requires one-time Microphone + Input Monitoring grants in System
        # Settings for whatever runs the daemon.
        hotkey.enabled = true;
        output = sharedSettings.output // {
          # macOS types natively via CGEvent; wtype/clipboard are Wayland tools.
          driver_order = [ ];
        };
      }
    );
  };
}
// lib.optionalAttrs platform.isLinux {
  services.voxtype = {
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
}
// lib.optionalAttrs platform.isDarwin {
  # launchd agent replaces the HM systemd user service, which is Linux-only.
  launchd.agents.voxtype = {
    enable = true;
    config = {
      Program = "${voxtype}/bin/voxtype";
      ProgramArguments = [
        "${voxtype}/bin/voxtype"
        "daemon"
      ];
      RunAtLoad = true;
      KeepAlive = {
        Crashed = true;
        SuccessfulExit = false;
      };
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/voxtype/stdout.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/voxtype/stderr.log";
    };
  };

  home.packages = [ voxtype ];

  # launchd does not create parent directories for the log paths above.
  home.activation.createVoxtypeLogDir = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    mkdir -p "${config.home.homeDirectory}/Library/Logs/voxtype"
  '';
}
