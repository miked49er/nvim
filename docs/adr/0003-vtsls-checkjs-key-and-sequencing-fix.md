# 0003: vtsls checkJs settings key and `<M-o>` sequencing fix

## Status

Accepted

## Context

Despite ADR-0002's fixes, the missing-import quickfix never actually worked:
`<M-CR>` in `.js` files never listed "Add missing import," and `<M-o>`'s
`source.addMissingImports.ts` step silently added nothing. Testing also
surfaced a second bug: `<M-o>`'s React-import restore step sometimes failed
to restore the import.

**Root cause of the missing-import failure:** `lua/plugins/lsp.lua` set

```lua
javascript = vim.tbl_deep_extend("force", {}, ts_js_language_settings, {
  implicitProjectConfig = { checkJs = true },
})
```

modeled on vscode's own `javascript.implicitProjectConfig.checkJs` /
`typescript.implicitProjectConfig.checkJs` settings. vtsls does not read
either of those keys. Reading vtsls's own bundled source
(`@vtsls/language-service/dist/index.js`, installed under mason's
`packages/vtsls`) and its `configuration.schema.json` shows it reads a single
flattened, non-language-split key instead: `js/ts.implicitProjectConfig.checkJs`
(`configuration.schema.json:104`). That value feeds
`ImplicitProjectConfiguration.readCheckJs` (~line 4592) →
`inferredProjectCompilerOptions()` (~line 4148-4159) → the arguments of a
`setCompilerOptionsForInferredProjects` tsserver request (~line 13503-13511),
re-sent on every config change that touches it (~line 13189-13190).

Since the key never matched, `checkJs` silently stayed `false`. This repo has
no tsconfig.json or jsconfig.json (confirmed, and none will be added), so
tsserver's inferred project never ran semantic checks on `.js` files, no
"cannot find name" diagnostic was ever produced, and neither the
diagnostic-gated `<M-CR>` quickfix nor the `source.addMissingImports.ts`
source action used by `<M-o>` had anything to compute a fix from — one root
cause behind both symptoms.

**Root cause of the React-import restore failure:** `<M-o>` sequenced
`source.organizeImports` → restore-check → `source.addMissingImports.ts` →
format using fixed `vim.defer_fn(..., 200)` timers between steps, rather than
waiting for each edit to actually land. If an edit round-trip (request →
response → `workspace/applyEdit`) took longer than 200ms, the next step read
a stale buffer. ADR-0002's Consequences section already flagged this class of
risk but left it unaddressed.

**Plugin swap considered and rejected:** `typescript-tools.nvim` talks to
tsserver directly and exposes `organize_imports`/`add_missing_imports` as
first-class code actions with a genuine request/response coroutine (no
timers) — a legitimately cleaner sequencing model. But its inferred-project
compiler options (`lua/typescript-tools/protocol/initialize.lua`) are a
hardcoded `default_compiler_options` table with no `checkJs` entry and no
exposed setting to add one; it's only ever overridden by an actual
tsconfig.json's `compilerOptions`. For a plain-JS project with none, there is
no way to enable `checkJs` at all with this plugin — a hard blocker, not just
a wrong key, and switching would also lose the eslint/inlay-hint/format
tuning already built up around vtsls. Rejected in favor of fixing vtsls
directly.

## Decision

- Moved the `checkJs` setting to vtsls's actual key: a new top-level
  `["js/ts"] = { implicitProjectConfig = { checkJs = true } }` in the vtsls
  `settings` table, removed from the `javascript` sub-table (which no longer
  needs to differ from `typescript`'s settings at all).
- Replaced `<M-o>`'s `defer_fn` timer chain with a `run_source_code_action`
  helper that sends `textDocument/codeAction` via `client:request` and only
  proceeds to the next step from that request's response callback — applying
  `action.edit` and, if present, running `action.command` via `client:exec_cmd`
  before calling `on_done`. This is the same "wait for the real round-trip"
  principle already used for `eslint.applyAllFixes` via `request_sync`
  (ADR-0002), just callback-based instead of blocking since this runs from a
  keymap rather than a `BufWritePre` hook.

## Consequences

- `<M-CR>`'s missing-import quickfix and `<M-o>`'s `addMissingImports` step
  now have a real diagnostic/source-fix to act on in plain `.js` files.
- `<M-o>` no longer has a fixed-latency assumption baked in; it scales with
  however long vtsls actually takes to respond, on slow projects or a cold
  server included.
- The React-import snapshot/restore special-case from ADR-0002 is unchanged
  in design, only in timing — it now runs strictly after `organizeImports`'s
  edit is confirmed applied.
