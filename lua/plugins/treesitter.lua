return {
  'nvim-treesitter/nvim-treesitter',
  lazy = false,
  build = ':TSUpdate',
  opts = {
    highlight = { enable = true },
  },
  config = function(_, opts)
    local config = require('nvim-treesitter')
    config.setup(opts)
    vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    config.install {
      'css',
      'dockerfile',
      'lua',
      'luadoc',
      'javascript',
      'typescript',
      'tsx',
      'java',
      'javadoc',
      'jsdoc',
      'json',
      'json5',
      'jsx',
      'kotlin',
      'make',
      'markdown',
      'powershell',
      'printf',
      'python',
      'regex',
      'ssh_config',
      'toml',
      'xml',
      'yaml',
      'zsh'
    }
  end
}
