# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Toodoos

A minimal macOS menu-bar todo app. Single-file Swift executable (~745 LOC in `Sources/Toodoos/main.swift`) that runs as a floating panel overlay. No Xcode project — built with Swift Package Manager.

- **Hotkey**: `Ctrl+Cmd+T` — single press opens input, double-tap (within 0.4s) opens todo list
- **Storage**: Plain markdown file at `~/.toodoos.md`, entries formatted as `- [ISO8601] text`
- **Logs**: `~/.toodoos.log`

## Build & Run

```bash
swift build                  # debug build
swift build -c release       # release build
.build/debug/Toodoos         # run debug binary
./bundle.sh                  # release build + install as ~/Applications/Toodoos.app
```

The `.app` bundle uses `LSUIElement=true` (set in Info.plist) to hide from the Dock. Do **not** call `setActivationPolicy(.accessory)` — it breaks window rendering on macOS 26+.

## Architecture

Everything lives in `main.swift` with these components:

- **Config** — file paths for storage and logging
- **TodoStorage** — read/write/rewrite `~/.toodoos.md` (append-only save, full rewrite on edit/delete)
- **FloatingInputWindow** (NSPanel) — borderless HUD input bar, top-center of screen. Uses `assertFocus()` retry loop to guarantee keyboard focus.
- **TodoListWindow** (NSPanel) — scrollable list of editable todos with delete buttons, undo stack (Cmd+Z), keyboard nav (arrow keys), Cmd+Delete to remove
- **HotKeyManager** — CGEvent tap (listen-only) for global hotkey. Polls for accessibility permission if not yet granted. Auto-re-enables if macOS disables the tap.
- **AppDelegate** — menu bar status item ("T"), hotkey routing (single/double-tap logic), auto-restart on wake via `execv` (workaround for stale window server connections after sleep)

## macOS Gotchas

- Requires **Accessibility permission** for the CGEvent tap. The app prompts once and polls until granted.
- The `execv` self-restart on wake is intentional — macOS invalidates the window server connection after sleep.
- Both windows use `collectionBehavior: [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]` to appear on all Spaces/fullscreen.
- The `.app` bundle preserves its directory structure across updates to avoid losing accessibility permissions.
