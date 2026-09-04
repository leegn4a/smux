---
name: smux
description: Control and message other tmux panes with tmux-bridge. Use for cross-pane agent communication or when reading or sending input to another pane; not for ordinary shell work or generic tmux configuration.
metadata:
  { "openclaw": { "emoji": "🖥️", "os": ["darwin", "linux"], "requires": { "bins": ["tmux", "tmux-bridge"] } } }
---

# smux

Use `tmux-bridge` for cross-pane interactions. It resolves pane labels, finds the
right tmux server, and enforces a read-before-act safeguard.

## Workflow

Before `type`, `exec`, `message`, or `keys`, run `read <target>`. Each action
consumes that read permission, so read again before the next action. `exec`
submits a trusted single-line command immediately; use `type`, then `read` and
`keys Enter` when the entered text needs verification before submission.

For an agent pane, do not sleep, poll, or read its pane for a reply after
submitting. The agent replies into this pane. For a normal shell or process,
read again when its output is needed.

To send an agent a message:

```bash
tmux-bridge read codex 20
tmux-bridge message codex 'Please review src/auth.ts'
tmux-bridge read codex 20
tmux-bridge keys codex Enter
```

`message` adds the sender pane and reply target automatically. When receiving
one, reply to the `pane:%N` target in its header using the same sequence.

For a shell command that does not need intermediate verification:

```bash
tmux-bridge read worker 20
tmux-bridge exec worker 'git status --short'
```

## Commands

| Command | Purpose |
|---|---|
| `list` | List panes and labels |
| `read <target> [lines]` | Capture pane output; also satisfies the read guard |
| `type <target> <text>` | Enter literal text without submitting |
| `exec <target> <command>` | Enter a literal command and submit it |
| `message <target> <text>` | Enter text with sender and reply details |
| `keys <target> <key>...` | Send special keys such as `Enter`, `Escape`, or `C-c` |
| `name <target> <label>` / `resolve <label>` | Set or look up a pane label |
| `id` / `doctor` | Show this pane ID or diagnose connectivity |

Targets may be a pane ID (`%3`), tmux target (`session:0.1`), window index, or
a label set with `name`.

Use raw `tmux` only for operations that `tmux-bridge` does not provide, such as
creating panes, choosing layouts, or managing sessions.
