{
  config,
  lib,
  pkgs,
  vars,
  ...
}:

let
  cfg = config.services.t3code;
  tailscale = lib.getExe config.services.tailscale.package;
  # T3 only logs a failed `tailscale serve`, so give tailscaled time to
  # connect after boot before the server starts.
  waitForTailscale = pkgs.writeShellScript "t3code-wait-for-tailscale" ''
    for _ in $(seq 60); do
      if ${tailscale} status --json 2>/dev/null \
        | ${lib.getExe pkgs.jq} -e '.BackendState == "Running"' >/dev/null; then
        exit 0
      fi
      sleep 1
    done
    echo "tailscale is not running; continuing without waiting" >&2
  '';
in
{
  options.services.t3code = {
    enable = lib.mkEnableOption "a headless T3 Code server exposed with Tailscale Serve";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3773;
      description = "Loopback port on which the T3 Code server listens.";
    };

    tailscaleServePort = lib.mkOption {
      type = lib.types.port;
      default = 443;
      description = "Tailnet HTTPS port that Tailscale Serve proxies to the server.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.tailscale.enable;
        message = "services.t3code requires services.tailscale.enable";
      }
    ];

    # Agents run in transient user scopes, so the user manager must outlive
    # login sessions.
    users.users.${vars.user}.linger = true;

    # A user unit, like `t3 service install`. The desktop app refuses to start
    # while this server owns ~/.t3.
    systemd.user.services.t3code = {
      description = "Headless T3 Code server";
      wantedBy = [ "default.target" ];
      unitConfig.ConditionUser = vars.user;

      environment = {
        PATH = lib.mkForce "${vars.home}/.local/bin:${vars.home}/.nix-profile/bin:/etc/profiles/per-user/${vars.user}/bin:/run/current-system/sw/bin:/run/wrappers/bin";
      };

      serviceConfig = {
        ExecStartPre = waitForTailscale;
        ExecStart = lib.escapeShellArgs [
          (lib.getExe' pkgs.t3code "t3")
          "serve"
          "--host"
          "127.0.0.1"
          "--port"
          (toString cfg.port)
          "--tailscale-serve"
          "--tailscale-serve-port"
          (toString cfg.tailscaleServePort)
        ];
        KillMode = "mixed";
        Restart = "always";
        RestartSec = 5;
        WorkingDirectory = vars.home;
      };
    };
  };
}
