{
  flake.modules.nixos.base =
    { lib, ... }:
    {
      services.openssh = {
        enable = true;
        ports = [ 22 ];
        openFirewall = true;
        settings = {
          AllowUsers = null;
          AuthenticationMethods = "publickey";
          KbdInteractiveAuthentication = false;
          PasswordAuthentication = false;
          PermitRootLogin = lib.mkDefault "no";
          PubkeyAuthentication = true;
          UseDns = true;
          X11Forwarding = false;
        };
      };
    };
}
