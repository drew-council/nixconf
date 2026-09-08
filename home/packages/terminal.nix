{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  nixProjectGenerator = pkgs.writeShellScriptBin "new-repo" ''
    exec ${inputs.nix-project-generator.apps.${pkgs.stdenv.hostPlatform.system}.default.program} "$@"
  '';

  portablePackages = with pkgs; [
    # General terminal tools
    uutils-coreutils-noprefix
    wget
    ripgrep
    fd
    unzip
    zip
    _7zz
    htop
    gitea
    cht-sh
    nerdfetch
    fastfetch
    ffmpeg
    imagemagick
    zstd
    nmap
    rclone
    lsof
    jc
    dig
    jq
    yq
    cowsay
    tetris
    xh
    dust
    dua
    hyperfine
    fselect
    ripgrep-all
    tokei
    wiki-tui
    just
    mask
    mprocs
    presenterm
    repgrep
    serie
    rainfrog
    atac
    tdx
    linear-cli
    secretspec
    clinfo
    rust-stakeholder
    file
    pastel
    termshot
    aha
    asciinema
    asciiquarium-transparent
    aria2
    yt-dlp
    xxd
    screen
    herdr # fancy terminal multiplexer
    tmux # simple terminal multiplexer
    (aspellWithDicts (dictionaries: with dictionaries; [ en ]))

    # Document tools
    glow
    typst
    mermaid-cli
    d2

    # Container clients
    docker-buildx
    dive
    traefik

    # Go tools
    go
    gopls

    # Python tools
    pyright
    uv
    ruff
    # ty # seems to be compiling from source?

    # Language tools
    markdown-oxide
    shellcheck
    protobuf-language-server
    buf
    zig
    odin
    ols
    rustc
    cargo
    rustfmt
    nodejs
    bun

    # Nix tools
    nix-output-monitor
    nixfmt
    nurl
    manix
    nix-search-cli
    nil
    nixd
    cachix
    nixProjectGenerator
  ];

  linuxPackages = with pkgs; [
    archivemount
    netscanner
    s-tui
    wavemon
    nvtop-appimage
  ];

  aiPackages = with inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}; [
    claude-code
    pi
  ];

  linuxAiPackages = with inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}; [ codex ];
in
{
  home.packages =
    portablePackages
    ++ aiPackages
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux (linuxPackages ++ linuxAiPackages);

  programs.nh = {
    enable = true;
    package = pkgs.nh-cachix;
  };
}
