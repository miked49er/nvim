return {
  {
    "mason-org/mason.nvim",
    opts = {},
  },
  {
    "mason-org/mason-lspconfig.nvim",
    opts = {
      ensure_installed = {
	"autohotkey_lsp",
	"awk_ls",
	"bashls",
	"cssls",
	"docker_language_server",
	"eslint",
	"gh_actions_ls",
	--'gopls',
	"gradle_ls",
	"graphql",
	"groovyls",
	"html",
	"jdtls",
	"jsonls",
	"kotlin_lsp",
	"lua_ls",
	"nextls",
	"openscad_lsp",
	"tailwindcss",
	"ts_ls",
	"yamlls",
      },
      automatic_enable = true,
    },
    dependencies = {
      { "mason-org/mason.nvim", opts = {} },
      "neovim/nvim-lspconfig",
    },
    config = function(_, opts)
      require("mason-lspconfig").setup(opts)
    end,
  },
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      {
	"folke/lazydev.nvim",
	ft = "lua", -- only load on lua files
	opts = {
	  library = {
	    -- See the configuration section for more details
	    -- Load luvit types when the `vim.uv` word is found
	    { path = "${3rd}/luv/library", words = { "vim%.uv" } },
	  },
	},
      },
    },
    opts = {
      servers = {
	lua_ls = {
	  settings = {
	    Lua = {
	      diagnostics = {
		globals = { "vim" },
	      },
	    },
	  },
	},
      },
    },
    config = function()
      --      local capabilities = require("cmp_nvim_lsp").default_capabilities()
      vim.lsp.config("lua_ls", {
	settings = {
	  capabilities = capabilities,
	},
      })

      vim.keymap.set({ "n" }, "<M-CR>", vim.lsp.buf.code_action, { desc = "LSP Code Action" })
    end,
  },
}
