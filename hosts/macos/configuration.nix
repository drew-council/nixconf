{
  lib,
  pkgs,
  vars,
  ...
}:
let
  # Declarative login item for a /Applications GUI app: RunAtLoad fires the
  # agent on every login, and `open -na` spawns the GUI app and returns
  # immediately, letting launchd consider the agent started. The path is
  # shell-quoted because the command runs via `sh -c` and app names may
  # contain spaces (e.g. "Scroll Reverser").
  loginItem = app: {
    command = "/usr/bin/open -na ${lib.escapeShellArg "/Applications/${app}.app"}";
    serviceConfig.RunAtLoad = true;
  };
in
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

  # OmniWM switches workspaces on a three-finger horizontal swipe (see
  # home/wm/omniwm); free the gesture from macOS's full-screen app swipe.
  # Four fingers still swipe between Spaces.
  system.defaults.trackpad.TrackpadThreeFingerHorizSwipeGesture = 0;

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

  # GUI apps from nixpkgs. nix-darwin links every .app in these packages into
  # /Applications/Nix Apps during activation, so Spotlight/Launchpad find them.
  environment.systemPackages = [
    pkgs.ytmdesktop # desktop app for youtube music (linux uses the same package via modules/packages/graphical.nix)
  ];

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
      # Menu bar utilities that must start at login; see launchd.user.agents
      # below for the login-item wiring.
      "maccy"
      "scroll-reverser"
    ];
  };

  # Login items for the casks above. Neither nix-darwin nor Home Manager
  # (at the locked revisions) ships modules for these apps, so run them as
  # user launchd agents instead (see loginItem above).
  launchd.user.agents = {
    maccy = loginItem "Maccy";
    scroll-reverser = loginItem "Scroll Reverser";
  };
}
