local actions = "config.lsp.actions"
return {
  { "n", "<leader>ih", { actions, "toggle_inlay_hints" }, "Toggle LSP inlay hints" },
  { "n", "<M-CR>", vim.lsp.buf.code_action, "LSP Code Action" },
  { "n", "<leader>zi", { actions, "toggle_import_fold" }, "Toggle imports fold" },
  { "n", "<M-o>", { actions, "organize_imports" }, "Add missing imports and organize" },
}
