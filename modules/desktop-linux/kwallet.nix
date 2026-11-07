{
  flake.modules.nixos.desktop-linux =
    { pkgs, ... }:
    {
      # enable kwallet for org.freedesktop.Secrets
      security.pam.services = {
        login.kwallet = {
          enable = true;
          package = pkgs.kdePackages.kwallet-pam;
        };
        kde = {
          allowNullPassword = true;
          kwallet = {
            enable = true;
            package = pkgs.kdePackages.kwallet-pam;
          };
        };
      };
      environment.systemPackages = with pkgs.kdePackages; [
        kwallet
        kwalletmanager
      ];
    };
}
