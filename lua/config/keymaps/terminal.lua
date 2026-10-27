local persistent = "config.terminal.persistent"
return {
  { "n", "<leader>st", { "config.terminal.term", "open_shell_split" }, "Open shell in bottom split" },
  { "t", "<Esc><Esc>", [[<C-\><C-n>]], "Exit terminal mode", { noremap = true, silent = true } },

  { { "n", "t" }, "<M-\\>", { persistent, "toggle" }, "Toggle persistent worktree terminal" },
  { { "n", "t" }, "<leader>\\h", { persistent, "toggle", "left" }, "Mount persistent worktree terminal left" },
  { { "n", "t" }, "<leader>\\j", { persistent, "toggle", "bottom" }, "Mount persistent worktree terminal bottom" },
  { { "n", "t" }, "<leader>\\k", { persistent, "toggle", "top" }, "Mount persistent worktree terminal top" },
  { { "n", "t" }, "<leader>\\l", { persistent, "toggle", "right" }, "Mount persistent worktree terminal right" },
}
