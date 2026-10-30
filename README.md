# nvim

A modular Neovim configuration with LSP support, treesitter syntax highlighting, and language server management via Mason.

## Features

- **Lazy loading** via [lazy.nvim](https://github.com/folke/lazy.nvim) for fast startup
- **Language Server Protocol (LSP)** with 20+ language servers
- **Syntax highlighting** via [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
- **Theme** using [tokyonight.nvim](https://github.com/folke/tokyonight.nvim)
- **Statusline** via [mini.nvim](https://github.com/echasnovski/mini.nvim)
- **Auto-formatting** on save for supported languages
- **Code actions** with <M-CR>

## External Dependencies

On macOS, run `./deps.sh` to install everything below (idempotent; prints an installed/skipped/failed summary). Add `--with-extras` for the optional toolchains. Exit codes: 0 ok, 1 an install failed, 2 usage error or unsupported OS. Required packages live in `Brewfile`, extras in `Brewfile.extras`.

### Required

- **[Neovim](https://neovim.io/)** (0.11+)
- **[Git](https://git-scm.com/)** — required for plugin installation
- **C compiler** and **make** — for building treesitter parsers and fzf-native (Xcode CLT on macOS)
- **[ripgrep](https://github.com/BurntSushi/ripgrep)**
- **[tree-sitter-cli](https://github.com/tree-sitter/tree-sitter)** — for building treesitter parsers
- **curl**, **unzip**, **tar**, **gzip** — used by Mason
- **[JetBrains Mono Nerd Font](https://www.nerdfonts.com/)**

### Optional

- **[Node.js](https://nodejs.org/)** — for TypeScript/JavaScript language servers (not installed by `deps.sh`; it warns if missing, use [nvm](https://github.com/nvm-sh/nvm))
- **[Python](https://www.python.org/)** — for Python language server
- **[Lua](https://www.lua.org/)** — for Lua language server

Installed by `./deps.sh --with-extras`:

- **[Go](https://golang.org/)** — for Go language server (commented out in config)
- **[Java Development Kit](https://www.oracle.com/java/technologies/downloads/)** (openjdk) — for Java language server
- **[Kotlin](https://kotlinlang.org/)**, **Gradle**, **Groovy**, **OpenSCAD**, **Docker**

## Language Servers

The following language servers are configured and will auto-install via [Mason](https://github.com/mason-org/mason.nvim):

- autohotkey_lsp — AutoHotkey
- awk_ls — AWK
- bashls — Bash/Shell
- cssls — CSS
- docker_language_server — Dockerfile
- eslint — ESLint
- gh_actions_ls — GitHub Actions
- gradle_ls — Gradle
- graphql — GraphQL
- groovyls — Groovy
- html — HTML
- jdtls — Java
- jsonls — JSON
- kotlin_lsp — Kotlin
- lua_ls — Lua
- nextls — Elixir
- openscad_lsp — OpenSCAD
- tailwindcss — Tailwind CSS
- ts_ls — TypeScript/JavaScript
- yamlls — YAML

## Installation

1. Clone this repository to your Neovim config directory:
   ```bash
   git clone https://github.com/miked49er/nvim.git ~/.config/nvim
   ```

2. Start Neovim:
   ```bash
   nvim
   ```

3. lazy.nvim will auto-bootstrap and install all plugins on first run

4. Mason language servers will auto-install when needed

## Keybindings

All mappings live in one file, `lua/config/keymaps/tables.lua`, grouped into
sections labeled by comments (Editor, Git, Telescope, Terminal, LSP) and loaded
by `keymaps/init.lua`. Read that file for the full list.

## Configuration Structure

```
nvim/
├── init.lua                  # Entry point
├── lua/
│   ├── config/
│   │   ├── lazy.lua         # lazy.nvim bootstrap
│   │   ├── keymaps/         # central keymap file (tables.lua) + loader
│   │   ├── git/             # repo, branch/ (ops, picker), worktree/ (identity, remove, tabs)
│   │   ├── lsp/             # LSP actions (organize imports, folds, hints)
│   │   ├── terminal/        # persistent per-worktree terminal
│   │   ├── ui/              # menu, palette
│   │   └── telescope/       # Telescope helpers
│   └── plugins/
│       ├── lsp.lua          # LSP configuration
│       ├── treesitter.lua   # Syntax highlighting
│       ├── theme.lua        # Colorscheme
│       └── mini.lua         # Statusline
└── .editorconfig            # Editor settings
```
