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

### Required

- **[Neovim](https://neovim.io/)** (0.9+)
- **[Git](https://git-scm.com/)** — required for plugin installation
- **C compiler** — required for building plugins like treesitter (gcc/clang/MSVC)

### Optional

- **[Node.js](https://nodejs.org/)** — for TypeScript/JavaScript language servers
- **[Python](https://www.python.org/)** — for Python language server
- **[Lua](https://www.lua.org/)** — for Lua language server
- **[Go](https://golang.org/)** — for Go language server (commented out in config)
- **[Java Development Kit](https://www.oracle.com/java/technologies/downloads/)** — for Java language server
- **[Kotlin](https://kotlinlang.org/)** — for Kotlin language server

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

- `<space><space>x` — Source current file
- `<leader>x` — Execute current line as Lua (normal mode)
- `<leader>x` — Execute selection as Lua (visual mode)
- `<M-CR>` — Show LSP code actions
- `yap` — Highlight when yanking text

## Configuration Structure

```
nvim/
├── init.lua                  # Entry point
├── lua/
│   ├── config/
│   │   └── lazy.lua         # lazy.nvim bootstrap
│   └── plugins/
│       ├── lsp.lua          # LSP configuration
│       ├── treesitter.lua   # Syntax highlighting
│       ├── theme.lua        # Colorscheme
│       └── mini.lua         # Statusline
└── .editorconfig            # Editor settings
```
