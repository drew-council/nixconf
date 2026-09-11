{
  lib,
  platform,
  ...
}:
{
  imports = [
    # keep-sorted start
    ./archive
    ./bat.nix
    ./btop.nix
    ./gh.nix
    ./glow.nix
    ./gs
    ./helix.nix
    ./herdr
    ./jujutsu.nix
    ./lazydocker.nix
    ./lazygit.nix
    ./nvim.nix
    ./tuicr
    # keep-sorted end
  ]
  ++ lib.optionals platform.isLinux [
    # Desktop applications and opnix secrets depend on NixOS/Wayland state.
    ./chromium.nix
    ./feh.nix
    ./firefox.nix
    ./op.nix
    ./spotify-player.nix
    ./vesktop.nix
    ./voxtype.nix
  ];

  programs = {
    # enable comma for command execution direct from nix-index search
    nix-index-database.comma.enable = true;

    # Keep Bash minimal for testing.
    nix-index.enableBashIntegration = false;
  };
}
