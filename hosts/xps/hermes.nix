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

  systemd.services.hermes-dashboard = {
    description = "Hermes Agent official web dashboard and chat";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "home-manager-${vars.user}.service"
    ];
    wants = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "${hermesHome}/.env";
    restartTriggers = [ managedConfig ];

    environment = {
      HOME = vars.home;
      HERMES_HOME = hermesHome;
      PATH = lib.mkForce "${vars.home}/.nix-profile/bin:/etc/profiles/per-user/${vars.user}/bin:/run/current-system/sw/bin:/run/wrappers/bin";
    };
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
