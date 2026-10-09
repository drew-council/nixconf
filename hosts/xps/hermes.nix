{
  inputs,
  lib,
  pkgs,
  vars,
  ...
}:
let
  hermes = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.hermes-agent;
  python = pkgs.python3.withPackages (p: [ p.pyyaml ]);
  hermesHome = "${vars.home}/.hermes";
  port = 9119;
  browserPort = 9223;
  # Public vault ID; authority is enforced by the read-only service-account token.
  agentAccessVault = "yioyf5x7vjgn2z53mz7gevaagy";
  browserProfile = "${hermesHome}/browser-agent-access";
  hermesEnvironment = {
    HOME = vars.home;
    HERMES_HOME = hermesHome;
    OP_LOAD_DESKTOP_APP_SETTINGS = "false";
    PATH = lib.mkForce "${vars.home}/.nix-profile/bin:/etc/profiles/per-user/${vars.user}/bin:/run/current-system/sw/bin:/run/wrappers/bin";
  };
  hermesOp = pkgs.writeShellApplication {
    name = "hermes-op";
    text = ''
      if [[ -z "''${OP_SERVICE_ACCOUNT_TOKEN:-}" ]]; then
        echo "Hermes requires its scoped service-account token; desktop authentication is disabled." >&2
        exit 78
      fi
      # Never fall back to the operator's desktop, session, or Connect credentials.
      unset OP_ACCOUNT OP_CONNECT_HOST OP_CONNECT_TOKEN
      export OP_LOAD_DESKTOP_APP_SETTINGS=false
      case "''${1:-}:''${2:-}" in
        item:list|item:get)
          for arg in "$@"; do
            case "$arg" in
              --vault|--vault=*)
                echo "Hermes fixes the vault to Agent Access." >&2
                exit 78
                ;;
            esac
          done
          # op item get requires --vault when authenticated as a service account.
          exec ${lib.getExe pkgs._1password-cli} "$@" --vault ${agentAccessVault}
          ;;
        *)
          echo "Hermes's 1Password wrapper supports only item list/get." >&2
          exit 78
          ;;
      esac
    '';
  };
  managedConfig = pkgs.writeText "hermes-xps-config.json" (
    builtins.toJSON {
      model = {
        provider = "openrouter";
        default = "mistralai/mistral-large-4-0";
        base_url = "https://openrouter.ai/api/v1";
      };
      delegation = {
        provider = "openrouter";
        model = "deepseek/deepseek-v4.1-flash";
        reasoning_effort = "high";
      };
      vault = {
        onepassword = {
          enabled = true;
          account = "";
          binary_path = lib.getExe hermesOp;
          service_account_token_env = "OP_SERVICE_ACCOUNT_TOKEN";
        };
        bitwarden.enabled = false;
      };
      browser = {
        # Use the native tools, including model-blind password/TOTP autofill.
        backend = "off";
        cdp_url = "http://127.0.0.1:${toString browserPort}";
        use_real_profile = false;
        record_sessions = false;
      };
      mcp_servers.composio = {
        url = "https://connect.composio.dev/mcp";
        headers."x-consumer-api-key" = "\${COMPOSIO_API_KEY}";
      };
    }
  );
in
{
  environment.systemPackages = [ hermes ];

  # Hermes and its dashboard edit/migrate config.yaml. Keep it writable while
  # applying these declarative settings on each Home Manager activation.
  home-manager.users.${vars.user} =
    { lib, ... }:
    {
      home.activation.hermesConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${python}/bin/python ${./hermes-configure.py} ${managedConfig} ${hermesHome}/config.yaml
      '';
    };

  # One private, persistent automation profile; never copy the desktop profile.
  # CDP carries browser authority and is deliberately loopback-only, not LAN-open.
  systemd.services.hermes-browser = {
    description = "Hermes persistent local automation browser";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    environment.HOME = vars.home;
    serviceConfig = {
      ExecStartPre = "${pkgs.coreutils}/bin/install -d -m 700 ${browserProfile}";
      ExecStart = "${lib.getExe pkgs.chromium} --headless=new --remote-debugging-address=127.0.0.1 --remote-debugging-port=${toString browserPort} --user-data-dir=${browserProfile} --password-store=basic --no-first-run --no-default-browser-check about:blank";
      User = vars.user;
      Group = "users";
      WorkingDirectory = vars.home;
      Restart = "on-failure";
      RestartSec = 5;
      UMask = "0077";
    };
  };

  # Standard Hermes messaging/cron gateway, supervised declaratively by NixOS.
  # The dashboard below owns the Android/WebSocket listener on port 9119.
  systemd.services.hermes-gateway = {
    description = "Hermes messaging and cron gateway";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "home-manager-${vars.user}.service"
      "hermes-browser.service"
    ];
    wants = [
      "network-online.target"
      "hermes-browser.service"
    ];
    unitConfig.ConditionPathExists = "${hermesHome}/.env";
    restartTriggers = [ managedConfig ];
    environment = hermesEnvironment // {
      HERMES_DASHBOARD = "0";
    };
    serviceConfig = {
      ExecStart = "${lib.getExe hermes} gateway run --external-supervisor";
      EnvironmentFile = "${hermesHome}/.env";
      User = vars.user;
      Group = "users";
      WorkingDirectory = vars.home;
      Restart = "on-failure";
      RestartSec = 5;
      RestartPreventExitStatus = [ 78 ];
      TimeoutStopSec = 180;
      UMask = "0077";
    };
  };

  systemd.services.hermes-dashboard = {
    description = "Hermes Agent official web dashboard and chat";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "home-manager-${vars.user}.service"
      "hermes-browser.service"
    ];
    wants = [
      "network-online.target"
      "hermes-browser.service"
    ];
    unitConfig.ConditionPathExists = "${hermesHome}/.env";
    restartTriggers = [ managedConfig ];

    environment = hermesEnvironment;
    serviceConfig = {
      ExecStart = "${lib.getExe hermes} dashboard --host 0.0.0.0 --port ${toString port} --no-open --skip-build";
      EnvironmentFile = "${hermesHome}/.env";
      User = vars.user;
      Group = "users";
      WorkingDirectory = vars.home;
      Restart = "on-failure";
      RestartSec = 5;
      RestartPreventExitStatus = [ 78 ];
      UMask = "0077";
    };
  };

  # Base disables the firewall; enable it only on XPS. Keep the existing service
  # allowances (including SSH), but expose the dashboard only to the home LAN.
  networking.firewall = {
    enable = lib.mkForce true;
    extraCommands = ''
      iptables -A nixos-fw -s 192.168.1.0/24 -p tcp --dport ${toString port} -j nixos-fw-accept
    '';
  };
}
