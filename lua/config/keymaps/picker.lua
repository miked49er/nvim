-- Named picker-internal actions -> { modes, lhs }, applied by the Telescope
-- adapter (config.ui.menu_adapter.telescope.bind).
return {
  back = { { "n", "i" }, "<Esc>" },
  toggle_select = { { "i", "n" }, "<Tab>" },
  confirm = { { "i", "n" }, "<CR>" },
  cancel = { { "i", "n" }, { "<Esc>", "<C-c>" } },
  skip = { { "i", "n" }, "<C-s>" },
}
