-- The one central keymap file. `keymaps` is the flat entry list registered by
-- config.keymaps (grouped by comment headers); `completion` and `picker` are
-- plugin-shaped data consumed by their owners.
local git = "config.git.branch.picker"
local lsp = "config.lsp.actions"
local files = "config.telescope.files"
local persistent = "config.terminal.persistent"

local keymaps = {
  -- Editor
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

  -- Git
  { "n", "<M-b>", { git, "open_menu" }, "Git branch/worktree menu" },
  { "n", "<leader>bb", { git, "switch_create_branch" }, "Switch/create git branch" },
  { "n", "<leader>bw", { git, "switch_create_worktree" }, "Switch/create git worktree" },
  { "n", "<leader>bp", { git, "pull" }, "Git pull" },
  { "n", "<leader>bP", { git, "push" }, "Git push" },

  -- Telescope
  { "n", "<leader>fh", { files, "help_tags" }, "Find help tags" },
  { "n", "<leader>fd", { files, "find_in_cwd" }, "Find files in cwd" },
  { "n", "<leader>en", { files, "find_in_config" }, "Find files in nvim config" },
  { "n", "<leader>ep", { files, "find_in_plugins" }, "Find files in plugin sources" },
  { "n", "<leader>fN", { files, "find_in_chosen_dir" }, "Find files in chosen directory" },
  { "n", "<leader>fg", { "config.telescope.multigrep", "live_multigrep" }, "Live multi-grep" },

  -- Terminal
  { "n", "<leader>st", { "config.terminal.term", "open_shell_split" }, "Open shell in bottom split" },
  { "t", "<Esc><Esc>", [[<C-\><C-n>]], "Exit terminal mode", { noremap = true, silent = true } },

  { { "n", "t" }, "<M-\\>", { persistent, "toggle" }, "Toggle persistent worktree terminal" },
  { { "n", "t" }, "<leader>\\h", { persistent, "toggle", "left" }, "Mount persistent worktree terminal left" },
  { { "n", "t" }, "<leader>\\j", { persistent, "toggle", "bottom" }, "Mount persistent worktree terminal bottom" },
  { { "n", "t" }, "<leader>\\k", { persistent, "toggle", "top" }, "Mount persistent worktree terminal top" },
  { { "n", "t" }, "<leader>\\l", { persistent, "toggle", "right" }, "Mount persistent worktree terminal right" },

  -- LSP
  { "n", "<leader>ih", { lsp, "toggle_inlay_hints" }, "Toggle LSP inlay hints" },
  { "n", "<M-CR>", vim.lsp.buf.code_action, "LSP Code Action" },
  { "n", "<leader>zi", { lsp, "toggle_import_fold" }, "Toggle imports fold" },
  { "n", "<M-o>", { lsp, "organize_imports" }, "Add missing imports and organize" },
}

-- blink.cmp `keymap` option, consumed by lua/plugins/completion.lua.
local completion = {
  preset = "default",

  ["<Tab>"] = {
    "select_and_accept",
    "snippet_forward",
    "fallback",
  },

  ["<S-Tab>"] = {
    "snippet_backward",
    "fallback",
  },
}

-- Named picker-internal actions -> { modes, lhs }, applied by the Telescope
-- adapter (config.ui.menu_adapter.telescope.bind).
local picker = {
  back = { { "n", "i" }, "<Esc>" },
  toggle_select = { { "i", "n" }, "<Tab>" },
  confirm = { { "i", "n" }, "<CR>" },
  cancel = { { "i", "n" }, { "<Esc>", "<C-c>" } },
  skip = { { "i", "n" }, "<C-s>" },
}

return { keymaps = keymaps, completion = completion, picker = picker }
