{
  lib,
  pkgs,
  vars,
  ...
}:
{
  networking.hostName = "macos";

  system = {
    primaryUser = vars.user;
    stateVersion = 7;
  };

  users.users.${vars.user} = {
    home = vars.home;
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;

  # nix-darwin builds PATH from environment.systemPath alone and never runs
  # /usr/libexec/path_helper, so nothing in /etc/paths.d ever lands on PATH --
  # Homebrew's bin dir in particular. Re-add the entries that exist here.
  #
  # mkOrder 1100 puts them after the Nix profiles (order 1000, so Nix always
  # wins a name collision) and before /usr/bin (order 1200).
  environment.systemPath = lib.mkOrder 1100 [
    # /etc/paths.d/homebrew; sbin is empty today but is where formulae like
    # sshd-keygen-wrapper land, and `brew shellenv` always exports both.
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
    # Listed in /etc/paths by macOS itself; holds safaridriver.
    "/System/Cryptexes/App/usr/bin"
  ];

  # Determinate owns the Nix daemon and its settings.
  nix.enable = false;

  # Declarative Homebrew: voxtype has no darwin build in nixpkgs, and the
  # upstream cask is the supported distribution (universal binary, quarantine
  # handled by the cask). cleanup stays "none" so hand-installed formulae are
  # untouched; only the tap/casks below are managed.
  homebrew = {
    enable = true;
    taps = [
      "peteonrails/voxtype"
    ];
    casks = [
      "peteonrails/voxtype/voxtype"
    ];
  };
}
