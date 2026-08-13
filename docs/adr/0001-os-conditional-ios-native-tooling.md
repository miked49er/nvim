# 0001: OS-conditional iOS native tooling

## Status

Accepted

## Context

This config is used on two machines: a Windows PC and a macOS work laptop, the
latter being where React Native (Expo) development actually happens. Expo
projects occasionally require looking at generated native `ios/`/`android/`
code, even in the managed workflow.

Android tooling (`jdtls`, `kotlin_lsp`) works identically on both platforms.
iOS tooling does not: the only real Swift language server, `sourcekit-lsp`,
ships with the Xcode toolchain and only runs on macOS — it cannot be
installed or run on Windows under any circumstances, mason-managed or
otherwise. `clangd` (for Objective-C) works cross-platform but is only useful
where iOS projects exist.

## Decision

`lua/plugins/lsp.lua` detects the OS via `vim.uv.os_uname().sysname` and only
configures/enables `sourcekit-lsp` and adds `clangd` to `ensure_installed`
when running on macOS (`is_mac`). On Windows, both are skipped entirely;
`.swift` files fall back to plain treesitter highlighting with no LSP.

## Consequences

- A single shared `lsp.lua` works correctly on both machines without manual
  edits when switching machines.
- Swift files get zero LSP support on Windows — this is a hard platform
  limitation, not a config gap, and won't be "fixed" by any nvim-side change.
- If a Linux machine is ever added to the rotation, `clangd` would still
  apply but `sourcekit-lsp` would need the same macOS-only gating.
