{ inputs, ... }:
{
  flake.modules.homeManager.terminal =
    { lib, pkgs, ... }:
    let
      nixProjectGenerator = pkgs.writeShellScriptBin "new-repo" ''
        exec ${inputs.nix-project-generator.apps.${pkgs.stdenv.hostPlatform.system}.default.program} "$@"
      '';

      portablePackages = with pkgs; [
        # General terminal tools
        uutils-coreutils-noprefix # rust coreutils
        wget # file downloader
        ripgrep # fast recursive search
        fd # fast file finder
        unzip # zip extraction
        zip # zip compression
        _7zz # 7-Zip archiver
        htop # process viewer
        gitea # self-hosted git forge
        cht-sh # cheat sheet lookup
        nerdfetch # shell startup system info
        fastfetch # detailed system info
        ffmpeg # audio and video conversion
        imagemagick # image conversion
        zstd # compression
        nmap # network scanner
        rclone # cloud storage sync
        lsof # list open files
        jc # convert command output to JSON
        dig # DNS lookup
        jq # JSON processor
        yq # YAML processor
        cowsay # talking cow
        tetris # terminal tetris
        xh # HTTP client
        dust # disk usage tree
        dua # interactive disk usage
        hyperfine # command benchmarking
        fselect # find files with SQL-like queries
        ripgrep-all # ripgrep for PDFs, archives, and more
        tokei # count lines of code
        wiki-tui # Wikipedia TUI
        just # command runner
        mask # task runner defined in markdown
        mprocs # run several commands side by side
        presenterm # terminal slideshows
        repgrep # interactive find and replace
        serie # git commit graph
        rainfrog # Postgres TUI
        atac # API client TUI
        tdx # markdown todo manager
        inputs.gh-stack-tui.packages.${pkgs.stdenv.hostPlatform.system}.ghst # stacked PR TUI
        inputs.gh-stack-tui.packages.${pkgs.stdenv.hostPlatform.system}.ghrv # review queue TUI
        linear-cli # Linear issue tracker CLI
        ntn # Notion CLI
        secretspec # declarative secrets
        rust-stakeholder # fake busy terminal output
        file # identify file types
        pastel # color manipulation
        termshot # screenshots of terminal output
        aha # ANSI to HTML
        asciinema # terminal session recorder
        asciiquarium-transparent # terminal aquarium
        aria2 # multi-connection downloader
        yt-dlp # video downloader
        xxd # hex dump
        bc # arbitrary precision calculator
        screen # serial console and multiplexer
        herdr # fancy terminal multiplexer
        tmux # simple terminal multiplexer
        signal-cli # CLI interactions with signal chat
        (aspellWithDicts (dictionaries: with dictionaries; [ en ])) # spell checker

        # Document tools
        glow # terminal markdown viewer
        typst # document typesetting
        mermaid-cli # render Mermaid diagrams
        d2 # text to diagrams

        # Container clients
        docker-buildx # extended docker builds
        dive # explore docker image layers
        traefik # reverse proxy

        # Go tools
        go # Go toolchain
        gopls # Go language server

        # Python tools
        pyright # Python type checker
        uv # Python package manager
        ruff # Python linter and formatter
        ty # Python type checker and language server

        # Language tools
        markdown-oxide # markdown language server
        shellcheck # shell script linter
        protobuf-language-server # protobuf language server
        buf # protobuf tooling
        zig # Zig toolchain
        odin # Odin compiler
        ols # Odin language server
        rustc # Rust compiler
        cargo # Rust package manager
        rustfmt # Rust formatter
        nodejs # JavaScript runtime
        bun # JavaScript runtime and toolkit

        # Nix tools
        nix-output-monitor # prettier Nix build output
        nixfmt # Nix formatter
        nurl # generate Nix fetcher calls
        manix # Nix documentation search
        nix-search-cli # search nixpkgs from the CLI
        nil # Nix language server
        nixd # Nix language server
        cachix # binary cache client
        nixProjectGenerator # new project template (`new-repo`)
      ];

      linuxPackages = with pkgs; [
        archivemount # mount archives with FUSE
        netscanner # network and WiFi scanner
        s-tui # CPU stress and monitoring TUI
        wavemon # wireless network monitor
        nvtopPackages.full # GPU process viewer
      ];

      aiPackages = with inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}; [
        claude-code # Claude Code agent
        pi # pi coding agent
      ];

      linuxAiPackages = with inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}; [
        codex # Codex coding agent
      ];
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
    };
}
