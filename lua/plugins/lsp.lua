local is_mac = vim.uv.os_uname().sysname == "Darwin"

local ensure_installed = {
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
  "vtsls",
  "yamlls",
}

if is_mac then
  -- Objective-C / native iOS headers. Swift itself needs sourcekit-lsp,
  -- which isn't mason-managed (ships with the Xcode toolchain).
  table.insert(ensure_installed, "clangd")
end

return {
  {
    "mason-org/mason.nvim",
    opts = {},
  },
  {
    "mason-org/mason-lspconfig.nvim",
    opts = {
      ensure_installed = ensure_installed,
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
    "b0o/schemastore.nvim",
  },
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "saghen/blink.cmp",
      "b0o/schemastore.nvim",
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
      local capabilities = require("blink.cmp").get_lsp_capabilities()

      vim.lsp.config("lua_ls", {
        settings = {
          capabilities = capabilities,
        },
      })

      -- TypeScript/TSX (React Native, Expo). Formatting is left to eslint
      -- below, not vtsls, since project eslint configs are the source of
      -- truth here rather than Prettier.
      vim.lsp.config("vtsls", {
        capabilities = capabilities,
        settings = {
          typescript = {
            inlayHints = {
              parameterNames = { enabled = "all" },
              parameterTypes = { enabled = true },
              variableTypes = { enabled = true },
              propertyDeclarationTypes = { enabled = true },
              functionLikeReturnTypes = { enabled = true },
              enumMemberValues = { enabled = true },
            },
          },
          javascript = {
            inlayHints = {
              parameterNames = { enabled = "all" },
              parameterTypes = { enabled = true },
              variableTypes = { enabled = true },
              propertyDeclarationTypes = { enabled = true },
              functionLikeReturnTypes = { enabled = true },
              enumMemberValues = { enabled = true },
            },
          },
        },
      })

      -- eslint owns formatting (source.fixAll.eslint) for JS/TS instead of
      -- vtsls's built-in formatter, since these projects use eslint, not
      -- Prettier.
      vim.lsp.config("eslint", {
        capabilities = capabilities,
        settings = {
          format = true,
        },
      })

      vim.lsp.config("jsonls", {
        capabilities = capabilities,
        settings = {
          json = {
            schemas = require("schemastore").json.schemas(),
            validate = { enable = true },
          },
        },
      })

      if is_mac then
        -- Swift, via the Xcode toolchain's sourcekit-lsp. Not mason-managed.
        vim.lsp.config("sourcekit", {
          cmd = { "xcrun", "sourcekit-lsp" },
          filetypes = { "swift", "objc", "objcpp" },
          capabilities = capabilities,
        })
        vim.lsp.enable("sourcekit")
      end

      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("my.lsp", {}),
        callback = function(ev)
          local client = assert(vim.lsp.get_client_by_id(ev.data.client_id))

          if client:supports_method("textDocument/inlayHint") then
            vim.lsp.inlay_hint.enable(true, { bufnr = ev.buf })
          end

          -- Auto-format ("lint") on save.
          -- Usually not needed if server supports "textDocument/willSaveWaitUntil".
          -- vtsls is excluded so it never fights eslint over JS/TS formatting.
          if
            client.name ~= "vtsls"
            and not client:supports_method("textDocument/willSaveWaitUntil")
            and client:supports_method("textDocument/formatting")
          then
            vim.api.nvim_create_autocmd("BufWritePre", {
              group = vim.api.nvim_create_augroup("my.lsp", { clear = false }),
              buffer = ev.buf,
              callback = function()
                vim.lsp.buf.format({ bufnr = ev.buf, id = client.id, timeout_ms = 1000 })
              end,
            })
          end
        end,
      })

      vim.keymap.set({ "n" }, "<M-CR>", vim.lsp.buf.code_action, { desc = "LSP Code Action" })
    end,
  },
}
