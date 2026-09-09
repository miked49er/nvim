# Persistent Per-Worktree Terminal

## Problem Statement

The config currently has two terminal entry points: `<leader>st` (a fixed 15-row split terminal that's wiped on close) and `<leader>tt` (a centered floating terminal). Neither persists any state per worktree — when working across multiple git worktrees in the same Neovim session (already supported via `worktree.lua`'s per-tab worktree detection and `tabline.lua`'s worktree icons), there is no way to keep a running shell tied to a specific worktree, return to it later, and visually tell it apart from the scratch `<leader>st` terminal.

## Solution

Replace the floating terminal (`<leader>tt`, `plugin/floaterminal.lua`) with a persistent terminal keyed by worktree path. It opens as a directional split (default: right, 30% width) instead of floating, remembers its last position/size per worktree across hide/show cycles within the session, is toggled and moved with a new `<M-\>` keybind family, and carries a `winbar` indicator (colored to match that worktree's existing tabline icon) so it's visually distinct from `<leader>st`. `<leader>st` is left untouched.

## User Stories

1. As a developer working across multiple git worktrees in one Neovim session, I want a terminal that stays tied to the worktree I opened it in, so that I don't lose shell context (cwd, running dev server, shell history) when I switch tabs to a different worktree.
2. As a developer, I want the persistent terminal to open as a split rather than a floating window, so that I can see my code and the terminal simultaneously without one obscuring the other.
3. As a developer, I want the persistent terminal to default to a right-hand split at 30% width, so that I get a sensible default layout without having to configure anything.
4. As a developer, I want additional keybinds to mount the terminal on the left, top, or bottom, so that I can adapt the layout to whatever I'm doing (e.g. a wide log at the bottom, a narrow assistant pane on the side).
5. As a developer, I want a single toggle keybind (`<M-\>`) to show/hide the current worktree's terminal, so that I can get it out of the way and bring it back without restarting my shell or losing scrollback.
6. As a developer, I want the terminal to reopen in the same side/size I last placed it at for that worktree, so that toggling doesn't fight my preferred layout each time.
7. As a developer, I want the persistent terminal to visually indicate which worktree it belongs to, so that I can't confuse it with the plain `<leader>st` scratch terminal or with another worktree's terminal.
8. As a developer, I want the worktree indicator's color to match the same worktree's tabline icon color, so that the visual language is consistent across the UI.
9. As a developer, I want `<leader>st` to keep working exactly as it does today, so that my existing muscle memory for a disposable scratch terminal isn't disrupted.
10. As a developer, I want the persistent terminal's shell job to only start the first time I open it for a given worktree, so that idle worktrees I never open a terminal in don't accumulate background shell processes.
11. As a developer, I want hiding the terminal (via `<M-\>`) to keep its shell job running in the background, so that long-running processes (dev servers, watchers) aren't interrupted just because I closed the split.
12. As a developer, I want manually closing the terminal window (`<C-w>q` or `:q`) to actually kill the shell job and wipe the buffer, so that I have a clear, intentional way to end a terminal instead of only ever being able to hide it.
13. As a developer, I want `:qa` (including via the Alpha dashboard's Quit button) to always succeed and cleanly terminate any persistent terminal jobs, so that quitting Neovim never gets blocked by a "job still running" error.
14. As a developer, I don't need Neovim to ask me for confirmation before force-closing terminals on quit, so that quitting stays fast and doesn't require distinguishing "idle" from "busy" shells.
15. As a developer, I want the persistent terminal to drop me into insert mode automatically when it opens, so that I can start typing commands immediately, consistent with the existing floating terminal's behavior.
16. As a developer, I want the persistent terminal to use the same shell (PowerShell on Windows, `$SHELL` elsewhere) as the other terminals in this config, so that behavior is consistent across all terminal types.
17. As a developer, I want the new keybind family to not collide with any of my existing Alt-chord bindings (`<M-j>`, `<M-k>`, `<M-CR>`, `<M-o>`, `<M-0>`, `<M-z>`, `<M-b>*`), so that adopting this feature doesn't break other workflows.

## Implementation Decisions

- **Scope of change:** `plugin/floaterminal.lua`'s floating terminal and its `<leader>tt` binding are removed/replaced entirely by the new module. `lua/config/terminal/term.lua` (`<leader>st`) is not modified. `lua/config/terminal/shell.lua`'s `M.open()` is reused unchanged as the job-spawning mechanism for the new terminal.
- **New module:** `lua/config/terminal/persistent.lua`, required from `init.lua` alongside the existing terminal modules. Exposes a `toggle(direction?)` entry point (direction optional; omitted = toggle current visibility using last-used or default side) plus the internal per-worktree state table.
- **Identity/keying:** terminal instances are keyed by worktree path, resolved via `worktree.branch_for_cwd(cwd) or worktree.label_for_cwd(cwd) or cwd` in that order — `branch_for_cwd` is tried first since it resolves for any git checkout (including the main worktree, which `label_for_cwd`'s `.claude/worktrees/<name>` pattern never matches), `label_for_cwd` is a fallback for the worktree-naming convention, and the raw cwd is the last resort for a non-git directory. All tabs/windows open on the same worktree share one terminal instance; a different worktree gets a separate instance. This same resolved string is what the winbar indicator displays.
- **State per worktree entry:** buffer id, job id, current window id (when visible), last-used side (`left`/`right`/`top`/`bottom`), last-used size (percentage of columns or lines depending on axis).
- **Spawn timing:** lazy. No buffer/job is created for a worktree until its terminal is toggled open for the first time. Nothing spawns on worktree/tab entry.
- **Persistence lifetime:** session-scoped only. Jobs are not restored across Neovim restarts; no external multiplexer or reattachment mechanism is introduced.
- **Default placement:** right split, 30% of `vim.o.columns`. Top/bottom mounts default to 30% of `vim.o.lines`. These are starting defaults, expected to be tuned after real-world use.
- **Keybinds:**
  - `<M-\>` — toggle show/hide of the current worktree's terminal, reopening at its last-used side/size (or the default if never moved).
  - `<M-\>h` / `<M-\>j` / `<M-\>k` / `<M-\>l` — move (and show) the terminal to left/bottom/top/right respectively, updating the remembered side/size for that worktree. Implemented as literal chorded keymap strings (`<M-\>h`, etc.) alongside the bare `<M-\>` mapping — this relies on Neovim's existing `timeoutlen`-based disambiguation between a complete short mapping and a longer one sharing its prefix, the same mechanism already used by `<M-b>` / `<M-b>b` / `<M-b>w` in `lua/config/telescope/git_branch.lua`.
  - `<leader>tt` is not reused or aliased — it becomes unbound.
- **Visibility toggling implementation:** spawning a worktree's first terminal uses `vnew`/`new` (a fresh empty buffer) for the split. Reopening an existing terminal instead uses a plain `vsplit`/`split` followed by `nvim_win_set_buf` to point the new window at the stored buffer — cheaper than creating and discarding another throwaway buffer just to immediately replace it. Both are sized/positioned per the stored side/size, analogous to how `plugin/floaterminal.lua` currently reuses `state.floating.buf` across opens. Hiding calls `nvim_win_hide` on the terminal's window — this does not unload the buffer (see the `bufhidden` override below), so the job keeps running.
- **Manual-close vs. toggle-hide disambiguation:** because both toggle-hide (`nvim_win_hide`) and a manual `<C-w>q`/`:q` fire the same window-close event from Neovim's perspective, the toggle function sets a short-lived module-level flag immediately before hiding. A `WinClosed` autocmd scoped to the terminal window checks this flag: if set, it's a toggle-hide and the autocmd does nothing (buffer stays loaded, job keeps running); if not set, it's a manual close, and the autocmd explicitly stops the job (`jobstop`) and wipes the buffer, freeing that worktree's state entry so the next toggle spawns a fresh job.
- **Quit safety:** a `VimLeavePre` autocmd iterates all tracked worktree terminal state entries and force-stops any live jobs before Neovim exits. This guarantees `:qa` (typed directly, or triggered via the Alpha dashboard's stock `startify`-theme Quit button, which calls a plain `:qa`) never fails with `E947: Job still running`. No confirmation prompt or "is something actively running" detection is implemented — quit always force-closes.
- **Visual indicator:** the terminal's window gets a window-local `winbar` (native Neovim option, no plugin dependency) showing a terminal glyph plus the resolved worktree key (see Identity/keying above), colored fg-only using `worktree.slot_for` / `worktree.color_for_slot` from `lua/config/worktree.lua` — the same fg-only styling `lua/config/tabline.lua` already uses to color each tab's worktree icon, so a given worktree's terminal indicator always matches its tab icon color. (`worktree.fg_for_bg` is a separate precedent used by `lua/plugins/mini.lua`'s statusline for a filled-background badge style; this indicator doesn't use it, since it has no fill to contrast against.) `<leader>st`'s split gets no winbar, preserving visual contrast.
- **Insert mode on open:** the terminal calls `startinsert()` when opened, matching current `plugin/floaterminal.lua` behavior.
- **`bufhidden` handling:** `lua/config/terminal/term.lua`'s existing `TermOpen` autocmd fires globally on *every* terminal buffer, including this module's (since both go through `config.terminal.shell.M.open()`'s `jobstart(..., { term = true })`), and sets `bufhidden = "wipe"`. Rather than adding a second, module-scoped `TermOpen` autocmd to race it, this module explicitly resets `bufhidden` back to `""` immediately after `shell.open()` returns (synchronously, within the same call that spawned the job) — simpler than coordinating two autocmds on the same event. `term.lua` itself is not modified. number/relativenumber-off still applies to this module's buffers via that shared autocmd.

## Testing Decisions

- Good tests here exercise the module's public behavior (worktree-keyed state transitions: open → hide → reopen-at-same-position → manual-close → respawn) rather than asserting on internal window/buffer IDs or Neovim API call sequences.
- No prior test coverage exists for `term.lua` or `floaterminal.lua` in this repo — this would be the first test coverage for any terminal-related module. The closest prior art is the pure-function testing style implied by `worktree.lua`'s `label_for_cwd`/`branch_for_cwd` (deterministic functions over plain inputs, no live Neovim state), which this module's state/placement logic should follow where possible.
- The `shell.open()` boundary (real `jobstart`/PowerShell spawning) should be stubbed/mocked in tests for `persistent.lua` — tests should verify that the module *calls* the shell-open seam correctly and tracks the returned job id, not that a real shell process starts.
- Modules to test: `lua/config/terminal/persistent.lua` (state transitions, side/size memory per worktree, toggle-vs-manual-close disambiguation logic, `VimLeavePre` cleanup covering all tracked jobs).
- Out of scope for testing: real window layout/geometry rendering (percentage-of-columns math can be unit tested as a pure calculation, but actual split creation is exercised only via manual verification, not automated tests, absent an existing Neovim-in-CI test harness in this repo).

## Out of Scope

- Cross-restart persistence (reattaching to a shell after quitting and reopening Neovim) — would require an external multiplexer or process-reattachment mechanism and is a separate, larger feature.
- Detecting whether a terminal has an "actively running" foreground process (vs. an idle shell prompt) to gate quit-time confirmation — evaluated (child-process enumeration via `Win32_Process`, or OSC 133 shell-integration markers) and explicitly rejected as not worth the added complexity/dependency for this iteration.
- A confirmation UI (e.g. a Telescope picker) before force-closing terminals on quit.
- Adopting `winbar` more broadly across the config (e.g. on all windows) — this session's indicator use is scoped to the persistent terminal only; broader adoption is a separate design decision.
- Keeping or aliasing `<leader>tt` to the new terminal — it is freed entirely.
- Any changes to `<leader>st` / `lua/config/terminal/term.lua`.

## Further Notes

- `<M-\>` was chosen over the initially proposed `` <M-`> `` after considering terminal-emulator reliability; the user accepted `` <M-`> `` may still be adjusted later if it doesn't feel right in practice, but the spec as written should use `<M-\>` as the base keybind — note: **the conversation that produced this spec ended on `<M-\>` as the confirmed choice** (see keybind decisions above).
- No issue tracker / triage label vocabulary was configured in this repo at spec-writing time (`/setup-matt-pocock-skills` has not been run), so this spec was written to `docs/specs/` instead of being published to a tracker. Run that setup and re-publish if a tracker-based workflow is wanted.
- Default sizes (30%/30%) are explicitly provisional — the user intends to test and adjust if they feel too large.
