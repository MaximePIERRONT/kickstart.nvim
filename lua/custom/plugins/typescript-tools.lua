return {
  {
    'pmizio/typescript-tools.nvim',
    ft = {
      'javascript',
      'javascriptreact',
      'typescript',
      'typescriptreact',
    },
    dependencies = {
      'nvim-lua/plenary.nvim',
      'neovim/nvim-lspconfig',
    },
    opts = {
      settings = {
        expose_as_code_action = {
          'add_missing_imports',
          'organize_imports',
        },
      },
    },
  },
}
