return {
  'stevearc/oil.nvim',
  lazy = false,
  keys = {
    { '<leader>o', '<cmd>Oil<cr>', desc = '[O]il - Open file explorer' },
  },
  opts = {
    default_file_explorer = true,
    columns = {
      'icon',
      'permissions',
      'size',
      'mtime',
    },
    view_options = {
      show_hidden = true,
    },
    keymaps = {
      ['g?'] = 'actions.show_help',
      ['<CR>'] = 'actions.select',
      ['<C-s>'] = 'actions.select_vsplit',
      ['<C-t>'] = 'actions.select_tab',
      ['<C-p>'] = 'actions.preview',
      ['<C-c>'] = 'actions.close',
      ['<C-l>'] = 'actions.refresh',
      ['-'] = 'actions.parent',
      ['_'] = 'actions.open_cwd',
      ['`'] = 'actions.cd',
      ['~'] = 'actions.tcd',
      ['g.'] = 'actions.toggle_hidden',
    },
  },
  config = function(_, opts)
    require('oil').setup(opts)
  end,
}
