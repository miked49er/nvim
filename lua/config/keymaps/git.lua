local picker = "config.git.branch.picker"
return {
  { "n", "<M-b>", { picker, "open_menu" }, "Git branch/worktree menu" },
  { "n", "<leader>bb", { picker, "switch_create_branch" }, "Switch/create git branch" },
  { "n", "<leader>bw", { picker, "switch_create_worktree" }, "Switch/create git worktree" },
  { "n", "<leader>bp", { picker, "pull" }, "Git pull" },
  { "n", "<leader>bP", { picker, "push" }, "Git push" },
}
