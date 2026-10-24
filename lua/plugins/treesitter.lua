return {
  'nvim-treesitter/nvim-treesitter',
  lazy = false,
  build = ':TSUpdate',
  config = function(_, opts)
    local config = require('nvim-treesitter')
    config.setup(opts)
    local languages = {
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
    config.install(languages)
    require('config.treesitter').setup(languages)
  end
}
