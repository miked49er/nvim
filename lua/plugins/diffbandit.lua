return {
  {
    "CoreyKaylor/diffbandit.nvim",
    config = function()
      local diffbandit = require("diffbandit")
      diffbandit.setup()
      vim.keymap.set("n", "<leader>gd", "<cmd>DiffBanditGit<CR>")
    end,
  },
}
