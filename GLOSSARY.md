# Context: nvim config

## Glossary

**RN toolchain** — The set of LSP/treesitter tooling this config activates for Expo-managed React Native development: TypeScript/TSX via `vtsls`, formatting via `eslint`, JSON schema validation via `jsonls` + `schemastore.nvim`, and CSS-in-JS highlighting for styled-components via the `css` treesitter parser injected into JS/TS.

**Native peek tooling** — LSP servers for occasionally-viewed native Android/iOS code inside an Expo project's generated `ios/`/`android/` directories, as opposed to primary development languages. Android is covered by the existing `jdtls`/`kotlin_lsp` servers. iOS is OS-conditional (see [[adr-0001]]): `clangd` for Objective-C, `sourcekit-lsp` for Swift, both only when running on macOS.

**Formatter of record** — For a given filetype, the single LSP client whose `textDocument/formatting` capability is actually invoked on save. For JS/TS/TSX this is `eslint` (via its `format` setting), not `vtsls` — `vtsls`'s own formatter is explicitly excluded in the `LspAttach` autocmd to avoid two clients fighting over the same buffer.

**Source code action** — An LSP code action offered independent of any diagnostic (e.g. `source.addMissingImports.ts`, `source.organizeImports`), as opposed to a **diagnostic-gated code action** (e.g. the "add missing import" quickfix), which only appears when the relevant diagnostic is present in the request's `context.diagnostics` — itself built from Neovim's diagnostic store, so a diagnostic dropped from that store client-side (see [[adr-0002]]) silently disables every quickfix gated on it, even though the diagnostic was genuinely computed server-side.

**Worktree name vs. branch name** — The worktree name is the basename of a git worktree's directory (as reported by `git worktree list`); the branch name is what's actually checked out inside it. This config's own worktree-creation flow derives the directory name from the branch name (slashes replaced with `+`), so the two normally match — but a worktree created by hand, or outside that convention, can have a directory name that diverges from its branch.

**Worktree** — A linked git checkout of this repo. This config keeps its own at `<main_repo_root>/.claude/worktrees/<sanitized branch name>` (see **Worktree identity**); the main checkout is listed by `git worktree list` too but is never offered for removal.

**Worktree identity** — What `config.git.worktree.identity` owns: the layout convention (name to path via `path_for`, path to folder name via `name_for_path`), and the shared answers tabs, terminals, tabline and branch picker agree on: a normalized root-directory key (`key_for_dir`), and a label (`label_for_dir`: branch, else layout folder name, else the dir). Matching is pure path work and spawns no git.

**Orphan worktree folder** — A folder under `.claude/worktrees/` that `git worktree list` no longer knows about, typically left when `git worktree remove` dropped the admin entry but could not delete the folder (e.g. a Windows file lock). The "Prune Worktree Folders" screen lists them and removes them through the same path as ordinary removal.

**Dirty worktree** — A worktree whose `git status` shows any change, untracked files included (they block a plain remove too). Locked worktrees are never treated as dirty and never force-removed. An orphan folder that is not its own checkout counts as dirty, since no git state says it is safe to drop; removal then asks whether to force, review each, or skip.
