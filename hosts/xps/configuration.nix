{
  config,
  vars,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Keep remote access available with the lid closed, on battery or AC power.
  # Explicit suspend and the power button keep their normal behavior.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };

  # NixOS uses reloadIfChanged for logind to avoid disrupting user sessions.
  # Tie its unit to the config file so switches actually reload changed policy.
  systemd.services.systemd-logind.restartTriggers = [
    config.environment.etc."systemd/logind.conf".source
  ];

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      AuthenticationMethods = "publickey";
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      PubkeyAuthentication = true;
    };
  };

  users.users."${vars.user}".openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINPILydKagpHBNoXFBEcUxqf4wFZDD6GRY09FGfLt/EH"
  ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?
}
