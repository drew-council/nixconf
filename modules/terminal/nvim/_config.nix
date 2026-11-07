{
  pkgs,
  ...
}:

let
  tree-sitter-flatbuffers = pkgs.tree-sitter.buildGrammar {
    language = "flatbuffers";
    version = "0.1.0+rev=95e6f9e";
    src = pkgs.fetchFromGitHub {
      owner = "yuanchenxi95";
      repo = "tree-sitter-flatbuffers";
      rev = "95e6f9ef101ea97e870bf6eebc0bd1fdfbaf5490";
      hash = "sha256-rxCgEpZ9NXjhq7ByJLtl/3Oy73dPv1EGG95k3eGOUVE=";
    };
    meta.homepage = "https://github.com/yuanchenxi95/tree-sitter-flatbuffers";
  };
in
# configure neovim using nixvim
{
  # This flake intentionally shares the host nixpkgs with nixvim.
  nixpkgs.source = pkgs.path;
  version.enableNixpkgsReleaseCheck = false;

  # set up color scheme
  colorschemes.catppuccin = {
    enable = true;
    settings = {
      flavor = "mocha";
      transparent_background = true;
    };
  };

  opts = {
    number = true; # show line numbers
    relativenumber = true; # show relative line numbers
    wrap = true; # wrap lines
    sidescroll = 1; # allow horizontal scrolling

    shiftwidth = 2; # tab width 2
    expandtab = true; # use spaces instead of tabs
    fileformat = "unix"; # set file format to unix

    exrc = true; # allow use of a local .nvimrc file

    clipboard = "unnamedplus"; # yank to and from system clipboard

    # show special characters
    list = true;
    listchars = "tab:▸▸,trail:·"; # show tabs and trailing whitespace

    mouse = "a"; # enable mouse mode
  };

  files."ftplugin/markdown.lua".localOpts = {
    shiftwidth = 2; # 2-space indent for markdown
    tabstop = 2;
  };

  globals.mapleader = " "; # sets the leader key to space
  globals.maplocalleader = "\\"; # sets the local leader key to \

  keymaps = [
    # use double leader to switch between buffers
    {
      mode = "n";
      key = "<leader><leader>";
      action = ":b#<CR>";
      options.desc = "Switch to previous buffer";
    }
    {
      mode = "n";
      key = "<leader>q";
      action = ":wq<CR>";
      options.desc = "Write file and quit";
    }

    # Octo keybinds
    {
      mode = "n";
      key = "<localleader>n";
      action = "<cmd>normal <localleader><Space>]u<CR>";
      options.desc = "Octo: mark file as viewed and move to next file";
    }
    {
      mode = "n";
      key = "<leader>os";
      action = "<cmd>lua if require('octo.reviews').get_current_review() then vim.cmd('Octo review submit') else vim.cmd('Octo review start') end<CR>";
      options.desc = "Octo: start or submit review";
    }
    {
      mode = "n";
      key = "<leader>oc";
      action = ":Octo review close<CR>";
      options.desc = "Octo: review close";
    }
    {
      mode = "n";
      key = "<leader>or";
      action = ":Octo review resume<CR>";
      options.desc = "Octo: review resume";
    }
  ];

  # language servers, configured via neovim's builtin vim.lsp.config
  # neovim already maps K, grn, gra, grr, gri, grt, gO, [d, ]d on attach
  lsp = {
    servers = {
      # keep-sorted start
      bashls.enable = true;
      cssls.enable = true;
      dockerls.enable = true;
      golangci_lint_ls.enable = true;
      gopls.enable = true;
      html.enable = true;
      jsonls.enable = true;
      lua_ls.enable = true;
      marksman.enable = true;
      nixd.enable = true;
      nushell.enable = true;
      ruff.enable = true;
      taplo.enable = true;
      ts_ls.enable = true; # also handles tsx/jsx
      ty.enable = true;
      typos_lsp.enable = true; # spell checking for code in any language
      yamlls.enable = true;
      # keep-sorted end
    };

    keymaps = [
      {
        key = "gd";
        lspBufAction = "definition";
      }
      {
        key = "<leader>lf";
        lspBufAction = "format";
      }
    ];
  };

  # golangci_lint_ls shells out to golangci-lint
  extraPackages = [ pkgs.golangci-lint ];

  plugins = {
    blink-cmp = {
      enable = true; # completion menu fed by LSP
      settings.sources.per_filetype.markdown = [
        "lsp"
        "path"
        "snippets"
      ]; # no word-from-buffer completions in markdown
    };
    direnv.enable = true;
    lspconfig.enable = true; # default server configs (cmd, filetypes, root markers)
    lualine.enable = true;
    octo.enable = true;
    oil.enable = true;
    scrollview.enable = true;
    telescope.enable = true;
    web-devicons.enable = true;

    # treesitter configuration
    treesitter = {
      enable = true;
      grammarPackages = pkgs.vimPlugins.nvim-treesitter.allGrammars ++ [
        tree-sitter-flatbuffers
      ];
      languageRegister.flatbuffers = "fbs";
      settings = {
        highlight = {
          enable = true;
          additional_vim_regex_highlighting = true;
        };
        indent.enable = true;
        incremental_selection.enable = true;
      };
    };
  };

  extraPlugins = [
    # plugin that toggles between relative and absolute line number based on mode
    (pkgs.vimUtils.buildVimPlugin {
      pname = "nvim-numbertoggle";
      version = "4b898b84d6f31f76bd563330d76177d5eb299efa";
      src = pkgs.fetchFromGitHub {
        owner = "sitiom";
        repo = "nvim-numbertoggle";
        rev = "4b898b84d6f31f76bd563330d76177d5eb299efa";
        hash = "sha256-NTcbTBzK9otf73dutdWpYwyphXhKVoa6sr5vTg56tLk=";
      };
    })

    # plugin that colorizes ANSI escape sequences
    (pkgs.vimUtils.buildVimPlugin {
      pname = "baleia";
      version = "1b25eac3ac03659c3d3af75c7455e179e5f197f7";
      src = pkgs.fetchFromGitHub {
        owner = "m00qek";
        repo = "baleia.nvim";
        rev = "1b25eac3ac03659c3d3af75c7455e179e5f197f7";
        hash = "sha256-qA1x5kplP2I8bURO0I4R0gt/zeznu9hQQ+XHptLGuwc=";
      };
    })
  ];

  filetype.extension.fbs = "fbs";

  # wrap each file in a do-block so its locals stay file-scoped
  extraConfigLua = pkgs.lib.concatMapStringsSep "\n" (f: "do\n${builtins.readFile f}\nend") [
    ./lua/markdown.lua
    ./lua/voice.lua
    ./lua/baleia.lua
  ];
}
