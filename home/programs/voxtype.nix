{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Keep the cached nixpkgs binary unchanged; only wrap credential loading.
  voxtype = pkgs.writeShellApplication {
    name = "voxtype";
    runtimeInputs = [
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
      export SSL_CERT_FILE="''${SSL_CERT_FILE:-${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt}"
      exec ${lib.getExe pkgs.voxtype} "$@"
    '';
  };
in
{
  programs.onepassword-secrets.secrets.voxtypeOpenai = {
    reference = "op://opnix/openai-personal/credential";
    path = "${config.xdg.configHome}/voxtype/openai-api-key";
    mode = "0600";
  };

  services.voxtype = {
    enable = true;
    package = voxtype;
    # Give the daemon's output drivers (wtype, wl-copy) access to the session.
    wayland.display = "wayland-1";
    # Deliberately no loadModels: remote-only, no model downloads or local inference.
    settings = {
      state_file = "auto";
      hotkey.enabled = false; # Hyprland bindings; no evdev/input-group access.
      audio.max_duration_secs = 120;
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
        driver_order = [
          "wtype"
          "clipboard"
        ];
        auto_submit = false;
        notification = {
          on_recording_start = true;
          on_recording_stop = true;
          on_transcription = false;
        };
      };
    };
  };
}
