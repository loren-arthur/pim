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

## Commands

- `:PimOpen` — open the conversation pane and start `pi --mode rpc`.
- `:PimClose` — close the conversation pane.
- `:PimToggle` — toggle the conversation pane.
- `:PimSend [prompt]` — send a prompt. If no prompt is provided, asks via `vim.ui.input`.
- `:'<,'>PimSendSelection [comment]` — send selected/ranged text plus optional comment.
- `:PimSteer [prompt]` — explicitly queue a steering message while pi is processing.
- `:PimFollowUp [prompt]` — explicitly queue a follow-up message after pi finishes current work.
- `:PimTranscript` — open the durable markdown transcript.
- `:PimTranscriptPath` — print the durable markdown transcript path.
- `:PimBridgeInfo` — print the local Neovim bridge port.
- `:PimAbort` — send RPC abort.
- `:PimStop` — stop the pi RPC subprocess.

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
- Parses strict JSONL from pi stdout.
- Opens a scratch `pim://conversation` buffer in a right-side vertical pane.
- Streams assistant `text_delta` updates into the conversation pane.
- Writes a durable markdown transcript and raw JSONL event log under `stdpath("state") .. "/pim/sessions"`.
- Rehydrates the conversation pane from the markdown transcript when reattaching to the same session.
- Displays basic tool start/end events.
- Sends plain prompts.
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
- Floating composer buffer.
- Rich UI for choosing steer vs follow-up per message.
- Tests.

## Repository layout

```text
plugin/pim.lua          command definitions
lua/pim/init.lua        public API and event routing
lua/pim/rpc.lua         pi RPC subprocess + JSONL client
lua/pim/buffer.lua      conversation buffer/pane rendering
lua/pim/context.lua     file/range/diagnostic context formatting
```
