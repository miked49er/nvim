return {
  {
    "CoreyKaylor/diffbandit.nvim",
    config = function()
      local diffbandit = require("diffbandit")
      diffbandit.setup()
      vim.keymap.set("n", "<M-0>", "<cmd>DiffBanditGit<CR>")
      vim.keymap.set("n", "<M-z>", "<cmd>DiffBanditDiscardHunk<CR>")
    end,
  },
}
