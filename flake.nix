{
  description = "NixOS, nix-darwin, and Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    import-tree.url = "github:denful/import-tree";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # secrets management through 1Password
    opnix = {
      url = "github:brizzbuzz/opnix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin = {
      url = "github:catppuccin/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Helium browser (Chromium fork); not yet in nixpkgs, repackages official .deb
    helium-browser = {
      url = "github:oxcl/nix-flake-helium-browser";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents.url = "github:numtide/llm-agents.nix";

    nix-project-generator = {
      url = "github:drew-council/nix-project-template";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    weave = {
      url = "github:ataraxy-labs/weave";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    };

    tdx = {
      url = "github:niklas-heer/tdx";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    tuicr = {
      url = "github:drew-council/tuicr/bizmythy-tweaks";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    gh-stack-tui = {
      url = "github:drew-council/gh-stack-tui";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.topiary-nushell.follows = "topiary-nushell";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    agent-artifacts = {
      url = "github:drew-council/agent-artifacts";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.topiary-nushell.follows = "topiary-nushell";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    # tracks the fork's patch branch; its CI keeps the pnpm deps hash current
    t3code = {
      url = "github:drew-council/t3code?ref=drew/local-patches";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    gchat-desktop = {
      url = "github:drew-council/gchat-desktop";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.topiary-nushell.follows = "topiary-nushell";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
    };

    systems = {
      url = "path:./flake.systems.nix";
      flake = false;
    };

    topiary-nushell = {
      url = "github:drew-council/topiary-nushell-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
