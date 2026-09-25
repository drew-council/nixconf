{
  pkgs,
  ...
}:

let
  baseConfig = import ../../nixvim { inherit pkgs; };
in
{
  # configure neovim using nixvim module
  # most settings same as package, but add some here
  programs.nixvim = baseConfig // {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  # allows use of nvim as pager
  home.packages = [ pkgs.nvimpager ];
}
