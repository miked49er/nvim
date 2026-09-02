local is_mac = vim.uv.os_uname().sysname == "Darwin"

-- Auto-fold the imports block on open. Set to false to leave imports
-- expanded and only fold them via the <leader>zi toggle.
vim.g.autofold_imports = false

local function import_fold_range(bufnr, callback)
  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/foldingRange" })
  if #clients == 0 then
    return
  end
  clients[1]:request("textDocument/foldingRange", {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
  }, function(err, result)
    if err or not result then
      return
    end
    for _, range in ipairs(result) do
      if range.kind == "imports" then
        callback(range)
        return
      end
    end
  end, bufnr)
end

local function close_import_fold(bufnr)
  import_fold_range(bufnr, function(range)
    local line = range.startLine + 1
    vim.api.nvim_win_call(vim.fn.bufwinid(bufnr), function()
      if vim.fn.foldclosed(line) == -1 then
        pcall(vim.cmd, string.format("%d,%dfoldclose!", line, range.endLine + 1))
      end
    end)
  end)
end

local function toggle_import_fold(bufnr)
  import_fold_range(bufnr, function(range)
    vim.api.nvim_win_call(vim.fn.bufwinid(bufnr), function()
      vim.api.nvim_win_set_cursor(0, { range.startLine + 1, 0 })
      vim.cmd("normal! za")
    end)
  end)
end

local all_servers = {
  "autohotkey_lsp",
  "awk_ls",
  "bashls",
  "cssls",
  "docker_language_server",
  "eslint",
  "gh_actions_ls",
  "gopls",
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
  table.insert(all_servers, "clangd")
end

-- Servers whose language server itself is generic/mason-managed, but which
-- are useless (and noisy) without an external, non-mason-managed toolchain
-- actually installed on this machine. Skip installing/enabling them when
-- the required executable(s) aren't on PATH, rather than erroring per-buffer.
local required_executables = {
  gopls = { "go" },
  jdtls = { "java" },
  kotlin_lsp = { "kotlin" },
  gradle_ls = { "gradle" },
  groovyls = { "groovy" },
  openscad_lsp = { "openscad" },
  docker_language_server = { "docker" },
  autohotkey_lsp = { "AutoHotkey", "AutoHotkeyU64" },
}

local function has_required_executable(name)
  local exes = required_executables[name]
  if not exes then
    return true
  end
  for _, exe in ipairs(exes) do
    if vim.fn.executable(exe) == 1 then
      return true
    end
  end
  return false
end

-- ts_ls is superseded by vtsls; exclude it in case it's still installed
-- from before the switch, since both would otherwise attach and offer
-- duplicate code actions (e.g. organizeImports).
local disabled_servers = { "ts_ls" }
local ensure_installed = {}
for _, name in ipairs(all_servers) do
  if has_required_executable(name) then
    table.insert(ensure_installed, name)
  else
    table.insert(disabled_servers, name)
  end
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
      automatic_enable = { exclude = disabled_servers },
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

      -- Suppress TS6133 specifically for unused `import React`, since the
      -- new JSX transform no longer requires it in scope.
      local publish_diagnostics = vim.lsp.handlers["textDocument/publishDiagnostics"]
      vim.lsp.handlers["textDocument/publishDiagnostics"] = function(err, result, ctx, config)
        if result and result.diagnostics then
          result.diagnostics = vim.tbl_filter(function(d)
            return not (d.code == 6133 and d.message == "'React' is declared but its value is never read.")
          end, result.diagnostics)

          -- checkJs is enabled below (via implicitProjectConfig) purely so
          -- vtsls's missing-import quickfix works in plain JS files, but we
          -- don't want the type errors that come with it: eslint is the
          -- linting source of truth for JS, so drop vtsls's diagnostics
          -- entirely in .js/.jsx buffers. TS/TSX buffers keep them.
          local client = vim.lsp.get_client_by_id(ctx.client_id)
          if client and client.name == "vtsls" and result.uri then
            local ft = vim.bo[vim.uri_to_bufnr(result.uri)].filetype
            if ft == "javascript" or ft == "javascriptreact" then
              result.diagnostics = {}
            end
          end
        end
        publish_diagnostics(err, result, ctx, config)
      end

      vim.lsp.config("lua_ls", {
        settings = {
          capabilities = capabilities,
        },
      })

      -- TypeScript/TSX (React Native, Expo). Formatting is left to eslint
      -- below, not vtsls, since project eslint configs are the source of
      -- truth here rather than Prettier.
      local ts_js_language_settings = {
        updateImportsOnFileMove = { enabled = "always" },
        format = {
          indentSize = 2,
          tabSize = 2,
          convertTabsToSpaces = true,
        },
        inlayHints = {
          parameterNames = { enabled = "all" },
          parameterTypes = { enabled = true },
          variableTypes = { enabled = true },
          propertyDeclarationTypes = { enabled = true },
          functionLikeReturnTypes = { enabled = true },
          enumMemberValues = { enabled = true },
        },
      }
      vim.lsp.config("vtsls", {
        capabilities = capabilities,
        settings = {
          typescript = ts_js_language_settings,
          -- checkJs so plain JS projects (no tsconfig/jsconfig) still get
          -- the "cannot find name" diagnostic that the missing-import
          -- quickfix depends on. The resulting type-error noise is dropped
          -- for .js/.jsx buffers in the publishDiagnostics wrapper above.
          javascript = vim.tbl_deep_extend("force", {}, ts_js_language_settings, {
            implicitProjectConfig = { checkJs = true },
          }),
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

      -- Off by default (session-only, via <leader>ih below) rather than
      -- always-on: constantly rendered hints turned out to be more
      -- annoying than useful day-to-day.
      local inlay_hints_enabled = false

      -- Inlay hints can crash with "Invalid 'col': out of range" when an
      -- extmark is redrawn against a line that's being actively edited
      -- (stale hint positions vs. new line length), so keep them off
      -- during insert mode regardless of the toggle state.
      vim.api.nvim_create_autocmd("InsertEnter", {
        group = vim.api.nvim_create_augroup("my.lsp.inlay_hint", {}),
        callback = function(ev)
          vim.lsp.inlay_hint.enable(false, { bufnr = ev.buf })
        end,
      })
      vim.api.nvim_create_autocmd("InsertLeave", {
        group = "my.lsp.inlay_hint",
        callback = function(ev)
          vim.lsp.inlay_hint.enable(inlay_hints_enabled, { bufnr = ev.buf })
        end,
      })

      vim.keymap.set("n", "<leader>ih", function()
        inlay_hints_enabled = not inlay_hints_enabled
        vim.lsp.inlay_hint.enable(inlay_hints_enabled)
        vim.notify("Inlay hints " .. (inlay_hints_enabled and "enabled" or "disabled"))
      end, { desc = "Toggle LSP inlay hints" })

      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("my.lsp", {}),
        callback = function(ev)
          local client = assert(vim.lsp.get_client_by_id(ev.data.client_id))

          if inlay_hints_enabled and client:supports_method("textDocument/inlayHint") then
            vim.lsp.inlay_hint.enable(true, { bufnr = ev.buf })
          end

          if client:supports_method("textDocument/foldingRange") and not vim.b[ev.buf].did_setup_lsp_folding then
            vim.b[ev.buf].did_setup_lsp_folding = true
            local win = vim.fn.bufwinid(ev.buf)
            vim.wo[win][0].foldmethod = "expr"
            vim.wo[win][0].foldexpr = "v:lua.vim.lsp.foldexpr()"
            vim.wo[win][0].foldlevel = 99

            if vim.g.autofold_imports then
              vim.defer_fn(function()
                close_import_fold(ev.buf)
              end, 100)
            end
          end

          -- eslint on save: use its own fixAll command (same as
          -- :LspEslintFixAll) rather than vim.lsp.buf.format, since
          -- textDocument/formatting only exposes a subset of the fixes
          -- eslint.applyAllFixes applies.
          if client.name == "eslint" then
            vim.api.nvim_create_autocmd("BufWritePre", {
              group = vim.api.nvim_create_augroup("my.lsp", { clear = false }),
              buffer = ev.buf,
              callback = function()
                -- :LspEslintFixAll fires workspace/executeCommand async and
                -- returns before the resulting workspace/applyEdit lands,
                -- so the write would race ahead of the fix. request_sync
                -- blocks until that round-trip (including the nested
                -- applyEdit) completes.
                client:request_sync("workspace/executeCommand", {
                  command = "eslint.applyAllFixes",
                  arguments = {
                    {
                      uri = vim.uri_from_bufnr(ev.buf),
                      version = vim.lsp.util.buf_versions[ev.buf],
                    },
                  },
                }, 1000, ev.buf)
              end,
            })
          -- Auto-format ("lint") on save for other servers.
          -- Usually not needed if server supports "textDocument/willSaveWaitUntil".
          -- vtsls is excluded so it never fights eslint over JS/TS formatting.
          elseif
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
      vim.keymap.set({ "n" }, "<leader>zi", function()
        toggle_import_fold(vim.api.nvim_get_current_buf())
      end, { desc = "Toggle imports fold" })

      vim.keymap.set({ "n" }, "<M-o>", function()
        local bufnr = vim.api.nvim_get_current_buf()
        -- Inlay hints can crash (see InsertEnter/InsertLeave above) when
        -- redrawn against a buffer mid-edit; organizeImports edits the
        -- buffer outside of insert mode, so guard it here too.
        vim.lsp.inlay_hint.enable(false, { bufnr = bufnr })
        vim.lsp.buf.code_action({
          apply = true,
          context = { only = { "source.organizeImports" }, diagnostics = {} },
        })
        vim.defer_fn(function()
          -- vtsls's own import formatting defaults to 4 spaces; let eslint
          -- (the project's formatting source of truth) fix it up.
          vim.lsp.buf.format({
            bufnr = bufnr,
            filter = function(client)
              return client.name ~= "vtsls"
            end,
            timeout_ms = 1000,
          })
          vim.lsp.inlay_hint.enable(inlay_hints_enabled, { bufnr = bufnr })
        end, 200)
      end, { desc = "Organize imports" })
    end,
  },
}
