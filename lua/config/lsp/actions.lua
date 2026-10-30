-- LSP actions bound by config.keymaps.tables, plus the state/helpers they share
-- with lua/plugins/lsp.lua (inlay-hint toggle, import folding).
local M = {}

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

function M.close_import_fold(bufnr)
  import_fold_range(bufnr, function(range)
    local line = range.startLine + 1
    vim.api.nvim_win_call(vim.fn.bufwinid(bufnr), function()
      if vim.fn.foldclosed(line) == -1 then
        pcall(vim.cmd, string.format("%d,%dfoldclose!", line, range.endLine + 1))
      end
    end)
  end)
end

function M.toggle_import_fold()
  local bufnr = vim.api.nvim_get_current_buf()
  import_fold_range(bufnr, function(range)
    vim.api.nvim_win_call(vim.fn.bufwinid(bufnr), function()
      vim.api.nvim_win_set_cursor(0, { range.startLine + 1, 0 })
      vim.cmd("normal! za")
    end)
  end)
end

-- Off by default (session-only, toggled via <leader>ih) rather than
-- always-on: constantly rendered hints turned out to be more
-- annoying than useful day-to-day.
local inlay_hints_enabled = false

function M.inlay_hints_enabled()
  return inlay_hints_enabled
end

function M.toggle_inlay_hints()
  inlay_hints_enabled = not inlay_hints_enabled
  vim.lsp.inlay_hint.enable(inlay_hints_enabled)
  vim.notify("Inlay hints " .. (inlay_hints_enabled and "enabled" or "disabled"))
end

-- Runs a single source code action (organizeImports/addMissingImports
-- are not diagnostic-gated) and calls on_done once its edit (and any
-- attached command, e.g. vtsls's telemetry no-ops) has actually been
-- applied, rather than guessing with a timer. See ADR-0003.
local function run_source_code_action(client, bufnr, kind, on_done)
  local params = vim.lsp.util.make_range_params(0, client.offset_encoding)
  params.context = { only = { kind }, diagnostics = {} }
  client:request("textDocument/codeAction", params, function(err, actions)
    local action = not err and actions and actions[1]
    if not action then
      on_done()
      return
    end
    if action.edit then
      vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding)
    end
    local a_cmd = action.command
    if a_cmd then
      local command = type(a_cmd) == "table" and a_cmd or action
      client:exec_cmd(command, { bufnr = bufnr }, on_done)
    else
      on_done()
    end
  end, bufnr)
end

function M.organize_imports()
  local bufnr = vim.api.nvim_get_current_buf()
  local client = vim.lsp.get_clients({ bufnr = bufnr, name = "vtsls" })[1]
  if not client then
    return
  end

  -- Inlay hints can crash (see InsertEnter/InsertLeave above) when
  -- redrawn against a buffer mid-edit; organizeImports edits the
  -- buffer outside of insert mode, so guard it here too.
  vim.lsp.inlay_hint.enable(false, { bufnr = bufnr })

  -- organizeImports treats `import React from "react"` as unused
  -- under the automatic JSX transform, but some projects still need
  -- it in scope for the classic transform (their eslint config
  -- enforces react/react-in-jsx-scope, a lint rule TypeScript's own
  -- diagnostics know nothing about, so source.addMissingImports.ts
  -- can't restore it — it only re-adds imports TS itself considers
  -- missing). Snapshot the import line so it can be restored
  -- verbatim (same quote style, semicolon) if organizeImports strips
  -- it. See ADR-0002.
  local react_import_pattern = "^import%s+React%s+from%s+['\"]react['\"];?%s*$"
  local react_import_line
  for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    if line:match(react_import_pattern) then
      react_import_line = line
      break
    end
  end

  -- Chain: organize/sort/dedupe imports first, then restore the
  -- React import if it got stripped, then add back any other
  -- missing imports (a source action, so it works regardless of
  -- whether the diagnostic-gated quickfix would have fired), then
  -- let eslint reformat it. Each step only starts once the previous
  -- edit is confirmed applied (see run_source_code_action) instead of
  -- being staggered with defer_fn timers.
  run_source_code_action(client, bufnr, "source.organizeImports", function()
    if react_import_line then
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local still_present, insert_at = false, 0
      for i, line in ipairs(lines) do
        if line:match(react_import_pattern) then
          still_present = true
          break
        elseif insert_at == 0 and line:match("^import%s") then
          insert_at = i - 1
        end
      end
      if not still_present then
        vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, { react_import_line })
      end
    end

    run_source_code_action(client, bufnr, "source.addMissingImports.ts", function()
      -- vtsls's own import formatting defaults to 4 spaces; let eslint
      -- (the project's formatting source of truth) fix it up.
      vim.lsp.buf.format({
        bufnr = bufnr,
        filter = function(c)
          return c.name ~= "vtsls"
        end,
        timeout_ms = 1000,
      })
      vim.lsp.inlay_hint.enable(inlay_hints_enabled, { bufnr = bufnr })
    end)
  end)
end

return M
