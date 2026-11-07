{
  flake.modules.nixos.server =
    { pkgs, ... }:
    {
      services.openssh.settings.PermitRootLogin = "prohibit-password";

      # Reached over ssh from terminals this host does not install.
      environment.systemPackages = [
        pkgs.ghostty.terminfo
        pkgs.kitty.terminfo
      ];
    };
}
