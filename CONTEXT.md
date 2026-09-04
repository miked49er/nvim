# Context: nvim config

## Glossary

**RN toolchain** — The set of LSP/treesitter tooling this config activates for Expo-managed React Native development: TypeScript/TSX via `vtsls`, formatting via `eslint`, JSON schema validation via `jsonls` + `schemastore.nvim`, and CSS-in-JS highlighting for styled-components via the `css` treesitter parser injected into JS/TS.

**Native peek tooling** — LSP servers for occasionally-viewed native Android/iOS code inside an Expo project's generated `ios/`/`android/` directories, as opposed to primary development languages. Android is covered by the existing `jdtls`/`kotlin_lsp` servers. iOS is OS-conditional (see [[adr-0001]]): `clangd` for Objective-C, `sourcekit-lsp` for Swift, both only when running on macOS.

**Formatter of record** — For a given filetype, the single LSP client whose `textDocument/formatting` capability is actually invoked on save. For JS/TS/TSX this is `eslint` (via its `format` setting), not `vtsls` — `vtsls`'s own formatter is explicitly excluded in the `LspAttach` autocmd to avoid two clients fighting over the same buffer.

**Source code action** — An LSP code action offered independent of any diagnostic (e.g. `source.addMissingImports.ts`, `source.organizeImports`), as opposed to a **diagnostic-gated code action** (e.g. the "add missing import" quickfix), which only appears when the relevant diagnostic is present in the request's `context.diagnostics` — itself built from Neovim's diagnostic store, so a diagnostic dropped from that store client-side (see [[adr-0002]]) silently disables every quickfix gated on it, even though the diagnostic was genuinely computed server-side.

**Worktree name vs. branch name** — The worktree name is the basename of a git worktree's directory (as reported by `git worktree list`); the branch name is what's actually checked out inside it. This config's own worktree-creation flow derives the directory name from the branch name (slashes replaced with `+`), so the two normally match — but a worktree created by hand, or outside that convention, can have a directory name that diverges from its branch.
