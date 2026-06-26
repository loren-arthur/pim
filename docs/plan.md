# pim plan

`pim` is a Neovim-native frontend for running pi over RPC. Neovim owns the editing UI; pi remains the agent engine.

## Product shape

- Conversation buffer/pane inside Neovim.
- Send prompts, selections, ranges, diagnostics, and comments from editor context.
- Stream pi responses and tool activity back into Neovim.
- Let pi inspect and, with appropriate controls, drive the current Neovim session.
- Preserve durable transcripts and raw event logs for reattachment/debugging.

## Current MVP

Implemented:

- Neovim commands for opening/toggling the conversation pane.
- Prompt sending, selection/range sending, steering, follow-ups, abort, and stop.
- `pi --mode rpc` subprocess management via JSONL.
- Streaming assistant text into `pim://conversation`.
- Durable markdown transcript plus raw JSONL event log under Neovim state.
- Local TCP JSONL Neovim bridge bound to `127.0.0.1` with a session token.
- Auto-loaded pi extension registering initial Neovim tools:
  - `nvim_open_file`
  - `nvim_highlight_range`
  - `nvim_clear_highlights`
  - `nvim_open_terminal`
  - `nvim_get_current_context`

## Design principles

1. **Semantic tools first**
   - Prefer explicit tools like `open_file` and `highlight_range` over raw Vim passthrough.
   - Raw Neovim command/Lua execution may be useful later, but should be opt-in and treated as dangerous.

2. **Trusted local prototype, safer product later**
   - Current bridge is intended for trusted local development.
   - Before wider use, add confirmation UI and permission policy for editor-driving tools.

3. **Neovim-native interaction**
   - Use buffers, windows, extmarks, diagnostics, virtual text, and terminal splits directly.
   - Avoid recreating a terminal chat UI inside Neovim when the editor can provide better primitives.

4. **Durable and inspectable state**
   - Keep markdown transcripts readable by humans.
   - Keep raw JSONL logs for debugging and future replay/reconstruction.

## Near-term roadmap

### 1. Chat UX and message navigation

Goal: make the conversation pane feel like a readable chat interface instead of a raw markdown-ish scratch buffer.

Planned changes:

- Add configurable syntax/highlight groups for user, assistant, system, error, and tool-use blocks. Initial role header groups are implemented, defaulting to blue user headers and purple assistant headers.
- Track user/assistant message starts with extmarks so navigation does not depend only on raw text scanning. Initial tracking is implemented; tool events are visually marked but skipped by message navigation.
- Render message headers consistently with timestamps/roles where useful.
- Visually distinguish streaming assistant text from completed assistant messages.
- Show a working/thinking indicator so users can tell pi is active and not stuck. Initial right-aligned status spinner is implemented.
- Use extmarks/signs/virtual text for tool starts, tool completions, and errors.
- Render enough tool argument context that users can tell what pi is doing without opening raw logs.
- Add fast navigation between messages:
  - next/previous message,
  - next/previous user message,
  - next/previous tool event,
  - jump to latest message.
- Add buffer-local mappings for chat navigation, with commands for users who prefer custom mappings.
- Default conversation-buffer jumps:
  - `<leader>j` for next message.
  - `<leader>k` for previous message.
- Keep the durable transcript human-readable even if the live buffer gets richer UI treatment.

Initial commands:

```vim
:PimNextMessage
:PimPrevMessage
:PimLatest
```

Possible later commands:

```vim
:PimNextTool
:PimPrevTool
```

### 2. Highlight and annotation UX

Goal: make agent-created visual marks useful and easy to dismiss.

Planned changes:

- Replace `nvim_buf_add_highlight` with extmark-based highlights using the configurable `PimHighlight` group by default. Initial implementation is done.
- Clear previous transient highlights before adding a new default highlight. Initial implementation is done with `clear_before_new = true`.
- Keep `:PimClearHighlights` for explicit cleanup.
- Add optional virtual text labels such as `pim` or `pi: relevant range`. Initial implementation is done via `label`, `virtualText`, and `default_label`.
- Track highlight IDs so future commands can clear one mark, one buffer, or all marks. Initial ID tracking is implemented; targeted clear commands are still future work.
- Document that `:nohlsearch` does not clear pim highlights because pim uses its own namespace.

Possible config:

```lua
require("pim").setup({
  highlights = {
    clear_before_new = true,
    timeout_ms = nil,
    virtual_text = true,
  },
})
```

### 3. Confirmation and permission policy

Goal: allow pi to drive Neovim while keeping the user in control.

Modes to consider:

- `observe`: pi can only inspect context.
- `suggest`: pi can propose actions but not run them.
- `confirm`: prompt before editor-changing actions.
- `drive`: trusted local mode for direct execution.

Initial actions needing policy:

- Opening files/windows/tabs.
- Opening terminals.
- Applying edits.
- Running raw Neovim commands, if added later.

### 4. Composer and inline comments

Goal: let the user write richer prompts/comments in real buffers.

Ideas:

> Loren note: prioritize the composer first. It should improve `:PimSend`, `:PimSendSelection`, longer steering/follow-up messages, and become the base for inline-comment workflows.

- Floating composer buffer for long prompts. Initial `:PimCompose` and `:PimComposeSelection` implementation is done.
- Inline annotations attached to code ranges via extmarks.
- Commands to collect annotations and send them as structured context.
- Buffer-local mappings for “send this comment/range to pim”.

### 5. Session/model controls

Goal: expose more Pi RPC capabilities in Neovim.

Ideas:

- Fresh session command. Initial `:PimNewSession [name]` / `:PimOpenFresh [name]` implementation is done.
- Session picker/switcher.
- Model picker.
- Compact/summarize controls.
- Reconstruct from Pi canonical session file when no pim transcript exists.

### 6. Tests and packaging

Goal: make the project safer to share and iterate on.

Needed:

- Lua syntax/load smoke tests.
- Bridge method tests where feasible.
- RPC JSONL framing tests.
- Minimal health check command.
- License and release notes.

## Open questions

- Should highlights be transient by default, persistent until cleared, or configurable per tool call?
- What is the right confirmation UX inside Neovim: `vim.ui.select`, floating window, command-line prompt, or custom buffer?
- Should pim eventually support raw Neovim passthrough behind an explicit dangerous option?
- How much of Pi's canonical session state should pim reconstruct versus relying on its own transcript?
- What is the smallest safe apply-edit workflow: patch preview buffer, quickfix list, or direct edit with confirmation?
