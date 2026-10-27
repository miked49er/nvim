return {
  { "n", "]d", function() vim.diagnostic.jump({ count = 1 }) end, "Next diagnostic" },
  { "n", "[d", function() vim.diagnostic.jump({ count = -1 }) end, "Previous diagnostic" },
  { "n", "<leader>D", vim.diagnostic.open_float, "Show diagnostic message" },

  { "n", "<space><space>x", "<cmd>source %<CR>", "Source current file" },
  { "n", "<leader>x", ":.lua<CR>", "Execute current line as Lua" },
  { "v", "<leader>x", ":lua<CR>", "Execute selection as Lua" },

  { "n", "<M-j>", "<cmd>cnext<CR>", "Next quickfix item" },
  { "n", "<M-k>", "<cmd>cprev<CR>", "Previous quickfix item" },

  { "n", "-", "<cmd>Oil<CR>", "Oil File Explorer" },
  { "n", "<leader>t", "<cmd>tabnew<CR>", "New tab" },

  { "n", "<M-0>", "<cmd>DiffBanditGit<CR>", "DiffBandit git diff" },
  { "n", "<M-z>", "<cmd>DiffBanditDiscardHunk<CR>", "DiffBandit discard hunk" },
}
