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

  plugins = {
    # keep-sorted start
    direnv.enable = true;
    lualine.enable = true;
    octo.enable = true;
    oil.enable = true;
    scrollview.enable = true;
    telescope.enable = true;
    web-devicons.enable = true;
    # keep-sorted end

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

  extraConfigLua = ''
    vim.filetype.add({
      extension = {
        fbs = "fbs",
      },
    })

    -- Wrap Markdown at whitespace instead of punctuation within words
    local default_breakat = vim.o.breakat
    local markdown_wrap_group = vim.api.nvim_create_augroup("MarkdownWrap", { clear = true })

    vim.api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
      group = markdown_wrap_group,
      pattern = "*",
      callback = function()
        if vim.bo.filetype == "markdown" then
          vim.opt_local.linebreak = true
          vim.o.breakat = " \t"
        else
          vim.o.breakat = default_breakat
        end
      end,
    })

    vim.api.nvim_create_autocmd("BufLeave", {
      group = markdown_wrap_group,
      pattern = "*",
      callback = function()
        if vim.bo.filetype == "markdown" then
          vim.o.breakat = default_breakat
        end
      end,
    })

    -- Pb command for Markdown buffers: wrap clipboard in fenced code block
    local pb_group = vim.api.nvim_create_augroup("MarkdownPb", { clear = true })
    vim.api.nvim_create_autocmd("FileType", {
      group = pb_group,
      pattern = "markdown",
      callback = function(args)
        vim.api.nvim_buf_create_user_command(args.buf, "Pb", function(opts)
          local text = vim.fn.getreg("+")
          if text == "" then
            text = vim.fn.getreg("*")
          end
          if text == "" then
            vim.api.nvim_echo({ { "pb: clipboard (+ register) is empty", "WarningMsg" } }, true, {})
            return
          end
          local block = vim.split(text, "\r?\n")
          while #block > 0 and block[#block] == "" do
            table.remove(block)
          end
          local lines = { "", "```" .. (opts.args or "") }
          for _, line in ipairs(block) do
            lines[#lines + 1] = line
          end
          lines[#lines + 1] = "```"
          lines[#lines + 1] = ""
          local row = vim.api.nvim_win_get_cursor(0)[1]
          vim.api.nvim_buf_set_lines(args.buf, row, row, false, lines)
          vim.api.nvim_win_set_cursor(0, { row + #lines, 0 })
        end, { nargs = "?", desc = "Wrap the clipboard in a Markdown code block below the current line" })
      end,
    })

    vim.cmd.cnoreabbrev("pb", "Pb")

    -- Baleia Setup
    vim.g.baleia = require("baleia").setup({ })

    -- Command to colorize the current buffer
    vim.api.nvim_create_user_command("BaleiaColorize", function()
      vim.g.baleia.once(vim.api.nvim_get_current_buf())
    end, { bang = true })

    -- Command to show logs
    vim.api.nvim_create_user_command("BaleiaLogs", vim.g.baleia.logger.show, { bang = true })
  '';
}
