{ inputs, ... }:
{
  flake.modules.homeManager.terminal =
    { lib, pkgs, ... }:
    {
      imports = [ inputs.nixvim.homeModules.nixvim ];

      # configure neovim using nixvim module
      # most settings same as package, but add some here
      programs.nixvim = lib.mkMerge [
        (import ./_config.nix { inherit pkgs; })
        {
          enable = true;
          defaultEditor = true;
          viAlias = true;
          vimAlias = true;
        }
      ];

      # allows use of nvim as pager
      home.packages = [ pkgs.nvimpager ];
    };
}
