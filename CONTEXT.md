# Context: nvim config

## Glossary

**RN toolchain** — The set of LSP/treesitter tooling this config activates for Expo-managed React Native development: TypeScript/TSX via `vtsls`, formatting via `eslint`, JSON schema validation via `jsonls` + `schemastore.nvim`, and CSS-in-JS highlighting for styled-components via the `css` treesitter parser injected into JS/TS.

**Native peek tooling** — LSP servers for occasionally-viewed native Android/iOS code inside an Expo project's generated `ios/`/`android/` directories, as opposed to primary development languages. Android is covered by the existing `jdtls`/`kotlin_lsp` servers. iOS is OS-conditional (see [[adr-0001]]): `clangd` for Objective-C, `sourcekit-lsp` for Swift, both only when running on macOS.

**Formatter of record** — For a given filetype, the single LSP client whose `textDocument/formatting` capability is actually invoked on save. For JS/TS/TSX this is `eslint` (via its `format` setting), not `vtsls` — `vtsls`'s own formatter is explicitly excluded in the `LspAttach` autocmd to avoid two clients fighting over the same buffer.
