local files = "config.telescope.files"
return {
  { "n", "<leader>fh", { files, "help_tags" }, "Find help tags" },
  { "n", "<leader>fd", { files, "find_in_cwd" }, "Find files in cwd" },
  { "n", "<leader>en", { files, "find_in_config" }, "Find files in nvim config" },
  { "n", "<leader>ep", { files, "find_in_plugins" }, "Find files in plugin sources" },
  { "n", "<leader>fN", { files, "find_in_chosen_dir" }, "Find files in chosen directory" },
  { "n", "<leader>fg", { "config.telescope.multigrep", "live_multigrep" }, "Live multi-grep" },
}
