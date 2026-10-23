{
  inputs,
  lib,
  pkgs,
  vars,
  ...
}:
let
  upstreamHermes = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.hermes-agent;
  # Dashboard /chat uses the Ink frontend over PTY.
  hermesFrontend = upstreamHermes.hermes-frontend.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./patches/hermes-vault-code.patch ];
    postBuild = (old.postBuild or "") + ''
      npm run build:ink --workspace ui-tui
      npm run test --workspace ui-tui -- \
        src/__tests__/vaultSaveLoginPrompt.test.tsx \
        src/__tests__/useInputHandlers.test.ts \
        src/__tests__/createGatewayEventHandler.test.ts
    '';
  });
  hermes = upstreamHermes.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./patches/hermes-nix-systemd.patch ];
    postPatch = (old.postPatch or "") + ''
      ${pkgs.python3}/bin/python tests/test_nix_systemd_unit.py
    '';
    makeWrapperArgs = map (
      arg: builtins.replaceStrings [ "${upstreamHermes.hermes-frontend}" ] [ "${hermesFrontend}" ] arg
    ) old.makeWrapperArgs;
    passthru = old.passthru // {
      hermes-frontend = hermesFrontend;
    };
  });
  hermesHome = "${vars.home}/.hermes";
  port = 9119;
  smsReceiverPort = 8788;
  browserPort = 9223;
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
in
{
  environment.systemPackages = [
    hermes
    hermesOp
  ];

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

  systemd.services.hermes-sms-receiver = {
    description = "Hermes MacroDroid SMS receiver";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "${hermesHome}/sms/webhook_receiver.py";
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${./hermes-sms-receiver.py} ${hermesHome}/sms/webhook_receiver.py --port ${toString smsReceiverPort}";
      User = vars.user;
      Group = "users";
      WorkingDirectory = "${hermesHome}/sms";
      Restart = "on-failure";
      RestartSec = 5;
      UMask = "0077";
    };
  };

  # Override the shared disabled firewall without dropping service allowances.
  networking.firewall = {
    enable = lib.mkForce true;
    extraCommands = ''
      iptables -A nixos-fw -s 192.168.1.0/24 -p tcp --dport ${toString port} -j nixos-fw-accept
      iptables -A nixos-fw -s 192.168.1.0/24 -p tcp --dport ${toString smsReceiverPort} -j nixos-fw-accept
    '';
  };
}
