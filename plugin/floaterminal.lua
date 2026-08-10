local shell = require("config.terminal.shell")

local state = {
  floating = {
    buf = -1,
    win = -1,
  },
}

---@param opts? { width?: number, height?: number }
local function create_floating_terminal(opts)
  opts = opts or {}

  local width = opts.width or math.floor(vim.o.columns * 0.8)
  local height = opts.height or math.floor(vim.o.lines * 0.8)

  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  local buf = vim.api.nvim_buf_is_valid(state.floating.buf) and state.floating.buf
      or vim.api.nvim_create_buf(false, true)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = col,
    row = row,
    style = "minimal",
    border = "rounded",
  })

  return { buf = buf, win = win }
end

local function toggle_floating_terminal(opts)
  if not vim.api.nvim_win_is_valid(state.floating.win) then
    state.floating = create_floating_terminal(opts)
    if vim.bo[state.floating.buf].buftype ~= "terminal" then
      shell.open()
    end

    vim.cmd.startinsert()
    return
  end

  vim.api.nvim_win_hide(state.floating.win)
end

vim.api.nvim_create_user_command("Floaterminal", toggle_floating_terminal, { desc = "Open a floating terminal" })

vim.keymap.set({ "n", "t" }, "<leader>tt", toggle_floating_terminal, { desc = "Toggle floating terminal" })
