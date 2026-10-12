{
  vars,
  ...
}:
let
  checkout = "${vars.home}/personal/placeparse";
  port = 8765;
  # tungsten's nginx-proxy-manager terminates HTTPS for this name.
  hostname = "peanutmap.home.drewcouncil.com";
in
{
  # Read-only map of restaurant replies from the placeparse checkout. It runs
  # the checkout's venv directly so it never syncs the environment the
  # outreach sender shares, and it cannot write to /home at all.
  systemd.services.peanut-map = {
    description = "placeparse peanut map (read-only web view)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "${checkout}/.venv/bin/python";
    environment = {
      HOME = vars.home;
      PYTHONDONTWRITEBYTECODE = "1";
    };
    serviceConfig = {
      ExecStart = "${checkout}/.venv/bin/python -m peanut_map --host 0.0.0.0 --port ${toString port} --allow-host ${hostname} --allow-host 192.168.1.145 --allow-host xps";
      User = vars.user;
      Group = "users";
      WorkingDirectory = checkout;
      Restart = "on-failure";
      RestartSec = 5;
      UMask = "0077";
      ProtectHome = "read-only";
      ProtectSystem = "strict";
      PrivateTmp = true;
      PrivateDevices = true;
      NoNewPrivileges = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
    };
  };

  # LAN only, like the Hermes dashboard; the proxy reaches it from tungsten.
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -s 192.168.1.0/24 -p tcp --dport ${toString port} -j nixos-fw-accept
  '';
}
