let
  # The Home Manager agent-artifacts host binds 127.0.0.1:41780 and rejects
  # any other Host header, so nginx re-serves it with the Host rewritten.
  upstream = "127.0.0.1:41780";
  port = 41781;
  listen = [
    {
      addr = "0.0.0.0";
      inherit port;
    }
  ];
in
{
  services.nginx = {
    enable = true;
    virtualHosts = {
      agent-artifacts = {
        serverName = "192.168.1.123";
        serverAliases = [
          "igneous"
          "igneous.lan"
        ];
        inherit listen;
        locations."/" = {
          proxyPass = "http://${upstream}";
          extraConfig = ''
            proxy_set_header Host ${upstream};
          '';
        };
      };
      # Keep the upstream's DNS-rebinding protection for unknown names.
      agent-artifacts-reject = {
        serverName = "_";
        default = true;
        inherit listen;
        locations."/".return = "403";
      };
    };
  };

  # LAN only; Twingate reaches it through the connector on truenas.
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -s 192.168.1.0/24 -p tcp --dport ${toString port} -j nixos-fw-accept
  '';
}
