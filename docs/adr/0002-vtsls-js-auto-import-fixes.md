# 0002: vtsls JS auto-import and organize-imports fixes

## Status

Accepted

## Context

Two JS-editing bugs traced back to the same root cause: the
`textDocument/publishDiagnostics` handler override in `lua/plugins/lsp.lua`
drops *all* vtsls diagnostics for `.js`/`.jsx` buffers before they reach
Neovim's diagnostic store (eslint is meant to be the sole visible diagnostic
source for JS). Since `checkJs` was enabled specifically so vtsls could
compute the "cannot find name" diagnostic the missing-import quickfix depends
on, emptying the store defeats that: `vim.lsp.buf.code_action()` builds its
request's `context.diagnostics` from the (now-empty) store, so the
diagnostic-gated missing-import fix never has anything to fire on via the
generic `<M-CR>` keymap. Completion-triggered auto-import is unaffected
because blink.cmp resolves `additionalTextEdits` independently of diagnostics.

Separately, triggering `<M-o>` ("organize imports") threw `Language server
'vtsls' does not support command '_typescript.didOrganizeImports'`. Since
vtsls is a thin LSP wrapper around VSCode's bundled TypeScript extension,
this command is carried straight through from VSCode's own
`organizeImports.ts`, where it's a pure telemetry no-op meant to be executed
by VSCode's command manager — not a real server command. Neovim's generic
LSP client has no such client extension, so it errors trying to run it.

## Decision

- `<M-o>` now chains `source.organizeImports` → `source.addMissingImports.ts`
  → the existing eslint-format defer step. `source.addMissingImports.ts` is a
  *source* action (not diagnostic-gated), the same pattern LazyVim uses for
  its own "add missing imports" keymap, so it works regardless of the
  diagnostic-store suppression below.
- `addMissingImports` turned out **not** to be self-correcting for the React
  case: `"'React' must be in scope when using JSX"` is an ESLint rule
  (`react/react-in-jsx-scope`), not a TypeScript diagnostic. Under this
  project's JSX transform setting, TypeScript's own compiler genuinely does
  not consider `React` missing, so `organizeImports` strips it as unused and
  `addMissingImports` has nothing to re-add — it only restores imports *TS*
  considers missing, and TS and this project's ESLint config disagree here.
  The `<M-o>` handler now snapshots the `import React from "react"` line (if
  present) before running `organizeImports`, and restores it verbatim if it
  got stripped, before the `addMissingImports` step runs. This is a
  deliberate special-case (not project-config-aware), scoped to this one
  import, accepted because the project's ESLint config still requires the
  classic transform while the nvim config's existing TS6133 filter assumes
  the modern one — a real mismatch, not a bug in either tool.
- `_typescript.didOrganizeImports` (and the sibling `_typescript.*` client
  commands vtsls attaches to other actions, e.g. `_typescript.applyRefactoring`)
  are stubbed as no-op client commands, since VSCode's own source confirms
  they do nothing but log telemetry.
- The `publishDiagnostics` override no longer drops vtsls diagnostics from
  the store for JS buffers. Instead it suppresses vtsls's *display* only
  (virtual text/signs/underline) for `.js`/`.jsx` buffers, scoped per-buffer
  so TS/TSX buffers keep showing vtsls diagnostics normally. This keeps the
  diagnostic store populated so the generic `<M-CR>` code action can also
  surface diagnostic-gated fixes (missing-import included) on JS buffers,
  while eslint remains the only diagnostic source actually rendered in JS.

## Consequences

- Two independent paths now add missing imports on JS buffers: the
  `<M-o>` chain (source action, always works) and `<M-CR>` (diagnostic-gated,
  now works because the store is no longer emptied).
- vtsls diagnostics are computed and stored for JS buffers even though never
  displayed — slightly more work per keystroke than outright dropping them,
  traded for code actions actually working.
- A separate, still-unconfirmed bug was observed where vtsls diagnostic
  noise briefly became visible in a JS buffer after triggering organize
  imports. Pull diagnostics were ruled out as the cause (vtsls doesn't
  implement `textDocument/diagnostic`/`workspace/diagnostic`). Left open to
  re-observe after these fixes land, since the command-execution error being
  stubbed away may have been an interacting factor.
