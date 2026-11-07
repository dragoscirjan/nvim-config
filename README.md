# 💤 LazyVim

A starter template for [LazyVim](https://github.com/LazyVim/LazyVim).
Refer to the [documentation](https://lazyvim.github.io/installation) to get started.

## Herd agent workspace

Herd manages independent Pi RPC sessions inside Neovim. Install a Pi CLI with JSONL RPC support and make `pi` available on `PATH`. Herd uses your normal Pi configuration and persistent conversation storage; it does not change agent permissions or isolate concurrent project writes.

Open the session picker with `<leader>h`, or create a session with `:HerdNew`. You choose each session's working directory explicitly. The default view is a centered, borderless, dark popup with its own session bar. Like `:Lazy`, it dims the code behind it when a non-transparent RGB background is available. Each Neovim tabpage has one reusable Herd view; selecting another agent changes that view's buffer rather than opening another window.

| Control | Action |
| --- | --- |
| `<leader>h` / `:HerdList` | Choose a session; create one if none exist |
| `<leader>hn` / `:HerdNew [root]` | Create a Pi session |
| `<leader>ht` / `:HerdToggle` | Show or hide the selected session |
| `<leader>hf` / `:HerdLayout` | Toggle the current Herd view between popup and docked split |
| `:HerdFloat` / `:HerdDock` | Select a presentation explicitly |
| `<leader>h]` / `<leader>h[` | Next or previous session in the same Herd view |
| Visual `<leader>hs` | Send selected lines and their source path |
| `<leader>ha` / `:HerdAbort` | Clear queued work and abort the active run |
| `<leader>hr` / `:HerdSteer [text]` | Steer the selected agent |
| `<leader>hk` / `:HerdStop` | Stop Pi but retain its transcript |
| `:HerdRename [name]` / double-click a tab | Rename a connected Pi session |
| `:HerdClose` / tab `×` button | Confirm, stop Pi, and remove its tab/buffer |

In a Herd buffer, Enter submits a prompt or queues a follow-up if the agent is busy. Escape returns to Normal mode; `q` hides the view without stopping its processes. Use normal Neovim window navigation when docked, or `<leader>ht` to return to the popup. Docking and floating preserve the agent process, transcript, and prompt draft.

Tabs use padded, subtly different active/inactive colors and `|` separators, without brackets. Their labels show activity first, then `π`, then `Session X` or the chosen name. Click a tab to select it, double-click to rename it, click `×` to close it after confirmation, or `+` to create another. Closing discards unsent drafts; hiding with `q` or stopping with `:HerdStop` does not remove the tab. When the view is narrow, `‹` / `›` indicate omitted sessions; cycle with the keyboard or use the picker. The selected session stays in the visible range.

Names must contain 1–80 characters and are stored through Pi's session metadata. Long names are shortened only for display. Pi does not write completely empty conversations to disk until they contain a message, so an unused session's name alone does not guarantee a saved conversation.

States: `○` idle, `◐` running, `?` awaiting input, `✓` finished while hidden, `!` failed, `×` stopped. Status indicators remain in Lualine when the popup is hidden. Supported Pi human-input requests open native dialogs; multiline input opens above the Herd popup.

Herd buffers are excluded from the main file bar through a composed Bufferline filter. They remain listed, so normal buffer commands can still reach them. Wiping a Herd buffer stops its Pi process. Exiting Neovim stops all owned processes, but Pi's conversation files remain.

To prefer docking, configure Herd before opening its first view:

```lua
require("herd").setup({ view = "split" })
```

This is an RPC frontend, not Pi's terminal UI: TUI-only commands and custom terminal extension UIs are unsupported. Transcript display is limited to 2 MiB/20,000 lines, with an explicit truncation marker. Images are represented by labels; Pi tools can also truncate their own output.

The broader multi-harness roadmap is tracked in [issue #8](https://github.com/dragoscirjan/nvim-config/issues/8). OpenCode/Claude adapters and standalone plugin extraction are not implemented yet.

### Tests

From the repository root, run `nvim --headless --clean -u NONE -l tests/herd/run.lua`.

The dependency-free suite uses temporary directories and fake Pi RPC subprocesses. It does not load LazyVim, install plugins, contact model providers, or use live Pi session storage.
