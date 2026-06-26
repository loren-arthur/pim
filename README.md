# pim

A self-contained Neovim plugin frontend for driving [pi](https://pi.dev) as an agent over RPC, with first-class editor context.

## Product direction

`pim` makes pi available from a Neovim-native conversation pane while preserving pi's full agent ability via `pi --mode rpc`.

Target workflows:

- Open/close a pi conversation buffer or pane from Neovim.
- Send prompts, selections, ranges, current file context, diagnostics, and user annotations to pi.
- Stream pi responses and tool events back into an editor buffer.
- Let the user comment directly on open code/docs, then submit those comments as structured context.
- Keep the human and agent grounded in the same files, ranges, and context docs.

## Why Neovim first

Initial target: **Neovim**.

Neovim has the right built-ins for this product shape: async jobs, Lua, floating windows/splits, extmarks, virtual text, diagnostics, namespaces, and LSP APIs. Vim support may be possible later with a reduced feature set, but supporting both from day one would slow the prototype.

## Install locally

With lazy.nvim:

```lua
{
  dir = "~/repo/pim",
  name = "pim",
  config = function()
    require("pim").setup({
      pi_cmd = { "pi", "--mode", "rpc" },
      pane = { width = 80 },
      -- Optional: make :PimOpen ask which per-directory session to use.
      session = { on_open = "select" },
      highlights = {
        PimUserHeader = { fg = "#268bd2", bold = true },
        PimAssistantHeader = { fg = "#6c71c4", bold = true },
        clear_before_new = true,
        virtual_text = true,
        default_label = "pi",
      },
    })
  end,
}
```

For a disposable test without touching your config:

```bash
nvim --clean \
  +'set rtp^=~/repo/pim' \
  +'runtime plugin/pim.lua' \
  +'lua require("pim").setup()'
```

## Running the tests

The repo ships with a 98-test plenary suite under `tests/`. Install
`plenary.nvim` somewhere on your runtime path:

```bash
mkdir -p ~/.local/share/nvim/site/pack/local/start
git clone --depth 1 https://github.com/nvim-lua/plenary.nvim \
  ~/.local/share/nvim/site/pack/local/start/plenary.nvim
```

Then, from the repo root:

```bash
nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/spec {minimal_init = 'tests/minimal_init.lua'}"
```

See [`tests/README.md`](tests/README.md) for the per-spec layout and a
single-spec invocation pattern.

## Commands

- `:PimOpen` — open the conversation pane and start `pi --mode rpc`.
- `:PimClose` — close the conversation pane.
- `:PimToggle` — toggle the conversation pane.
- `:PimNewSession [name]` — start a fresh pi session in the current pim RPC process. If no name is provided, pim generates one from the cwd and timestamp.
- `:PimOpenFresh [name]` — open pim and immediately start a fresh pi session.
- `:PimOpenSelect` — open pim with a selector of sessions tied to the current directory plus a fresh-session option.
- `:PimSessionInfo` — show current and workspace-pinned session metadata.
- `:PimForgetSession` — forget the workspace-pinned session for the current cwd.
- `:PimSend [prompt]` — send a prompt. If no prompt is provided, opens the floating composer.
- `:'<,'>PimSendSelection [comment]` — send selected/ranged text plus optional comment. If no comment is provided, opens the floating selection composer.
- `:PimCompose` — open a floating markdown composer for a longer prompt (`<C-s>` submits, `q` cancels).
- `:'<,'>PimComposeSelection` — open a floating composer for a comment on the selected/ranged text.
- `:PimSteer [prompt]` — explicitly queue a steering message while pi is processing.
- `:PimFollowUp [prompt]` — explicitly queue a follow-up message after pi finishes current work.
- `:PimTranscript` — open the durable markdown transcript.
- `:PimTranscriptPath` — print the durable markdown transcript path.
- `:PimBridgeInfo` — print the local Neovim bridge port.
- `:PimClearHighlights` — clear highlights created by pim's Neovim bridge.
- `:PimNextMessage` — jump to the next conversation message.
- `:PimPrevMessage` — jump to the previous conversation message.
- `:PimLatest` — jump to the latest conversation line.
- `:PimAbort` — send RPC abort.
- `:PimStop` — stop the pi RPC subprocess.
- `:PimModel` — interactively pick the pi model (via `vim.ui.select`, so telescope/fzf/snacks themes apply); the choice is written to settings and pi reloads. The current model is marked.
- `:PimModelEdit` — open pi's model settings file (`~/.pi/agent/settings.json`) for manual editing.
- `:PimReload` — restart pi (resuming the current session) so edited config/model settings take effect.

## Keymaps

Default keymaps are created under a `<leader>p` prefix (set `keymaps = false` in
`setup` to disable, or `keymaps = { prefix = "<leader>x" }` to change it). Make
sure `mapleader` is set before `setup` runs.

- `<leader>pp` — toggle the conversation pane.
- `<leader>ps` — send a prompt (normal) / send the selection (visual).
- `<leader>pS` — steer.
- `<leader>pf` — follow up.
- `<leader>pm` — pick the model.
- `<leader>pr` — reload pi.
- `<leader>pa` — abort.
- `<leader>px` — stop pi.
- `<leader>pt` — open the transcript.

## Current prototype behavior

Implemented:

- Starts a local Neovim TCP JSONL bridge on `127.0.0.1`.
- Auto-loads `pi/nvim-bridge.ts` into pi with `-e` and passes bridge env vars.
- Registers first pi tools for controlling Neovim:
  - `nvim_open_file`
  - `nvim_highlight_range`
  - `nvim_clear_highlights`
  - `nvim_open_terminal`
  - `nvim_get_current_context`
- Starts `pi --mode rpc` as a Neovim job.
- Requests and displays Pi RPC session state with `get_state`.
- Remembers the last session file per workspace under Neovim state and can resume that exact file on next open when `pi_cmd` does not already specify an explicit session mode.
- Can show a per-directory session selector on open via `session = { on_open = "select" }`.
- Can start a fresh session through Pi RPC `new_session` and optionally name it; unnamed fresh sessions get generated cwd/timestamp names.
- Parses strict JSONL from pi stdout.
- Opens a scratch `pim://conversation` buffer in a right-side vertical pane.
- Adds buffer-local `<leader>j` / `<leader>k` mappings in the conversation buffer for next/previous message navigation.
- Shows a right-aligned spinner/status in the conversation buffer while pi is working or running tools.
- Uses configurable `PimUserHeader`, `PimAssistantHeader`, `PimToolHeader`, `PimErrorHeader`, `PimSystemHeader`, `PimHighlight`, `PimStatusWorking`, and `PimStatusIdle` highlight groups that users can override. Defaults use blue for user headers and purple for assistant headers.
- Renders agent-created file/range highlights as clearable extmarks with optional virtual text labels.
- Streams assistant `text_delta` updates into the conversation pane.
- Writes a durable markdown transcript and raw JSONL event log under `stdpath("state") .. "/pim/sessions"`.
- Rehydrates the conversation pane from the markdown transcript when reattaching to the same session.
- Displays tool start/end events with concise argument context.
- Sends plain prompts.
- Opens a floating composer buffer for longer prompts and selected-range comments.
- Automatically sends new prompts/ranges as steering messages when pi is already processing, avoiding Pi RPC's `Agent is already processing` error.
- Supports explicit `:PimSteer` and `:PimFollowUp` commands.
- Sends selected ranges with:
  - file path,
  - line range,
  - selected text,
  - diagnostics in range from `vim.diagnostic`,
  - optional user comment.

Not implemented yet:

- Confirmation UI / permission policy for Neovim-driving tools. Current bridge is intended for trusted local use while bootstrapping.
- Full reconstruction from Pi's canonical session file when no local pim transcript exists.
- Rich tool result rendering.
- Session/model controls.
- Extension UI request handling.
- Inline persistent annotations/extmarks.
- Rich UI for choosing steer vs follow-up per message.
- Tests.

## Plan

See [`docs/plan.md`](docs/plan.md) for roadmap, design principles, and open questions.

## Repository layout

```text
plugin/pim.lua          command definitions
lua/pim/init.lua        public API and event routing
lua/pim/rpc.lua         pi RPC subprocess + JSONL client
lua/pim/buffer.lua      conversation buffer/pane rendering
lua/pim/composer.lua    floating prompt/comment composer
lua/pim/context.lua     file/range/diagnostic context formatting
lua/pim/bridge.lua      local Neovim TCP bridge and editor-control methods
lua/pim/transcript.lua  durable markdown transcript and raw JSONL event log
pi/nvim-bridge.ts       pi extension registering Neovim bridge tools
docs/plan.md            roadmap, design principles, and open questions
```
