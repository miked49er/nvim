return {
  {
    "CoreyKaylor/diffbandit.nvim",
    config = function()
      local diffbandit = require("diffbandit")
      diffbandit.setup()
    end,
  },
}
