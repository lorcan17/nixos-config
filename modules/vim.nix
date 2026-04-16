{ pkgs, ... }:
{
  home-manager.users.lorcan = {
    programs.neovim = {
      enable        = true;
      defaultEditor = true;
      vimAlias      = true;
      viAlias       = true;
      withRuby      = false;
      withPython3   = false;

      plugins = with pkgs.vimPlugins; [
        telescope-nvim
        nvim-treesitter.withAllGrammars
        nvim-lspconfig
        comment-nvim
        nvim-autopairs
        gitsigns-nvim
        which-key-nvim
        catppuccin-nvim
        lualine-nvim
      ];

      # extraLuaConfig was renamed to initLua
      initLua = ''
        vim.g.mapleader = " "
        vim.opt.number         = true
        vim.opt.relativenumber = true
        vim.opt.expandtab      = true
        vim.opt.shiftwidth     = 2
        vim.opt.tabstop        = 2

        local lspconfig = require('lspconfig')
        lspconfig.nil_ls.setup{}
        lspconfig.pyright.setup{}
        lspconfig.yamlls.setup{}

        local builtin = require('telescope.builtin')
        vim.keymap.set('n', '<leader>ff', builtin.find_files)
        vim.keymap.set('n', '<leader>fg', builtin.live_grep)
        vim.keymap.set('n', '<leader>fb', builtin.buffers)
      '';
    };

    home.packages = with pkgs; [
      nil
      pyright
      yaml-language-server
    ];
  };
}
