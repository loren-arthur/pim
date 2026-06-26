# pim tests

The plugin ships with a plenary.nvim-based test suite that lives entirely
under this `tests/` directory. The suite is the actual safety net for
refactors, and it now has 98 tests spanning every module.

## Layout

```
tests/
  minimal_init.lua             # Headless nvim init for the suite
  helpers/
    fixtures.lua               # Sample settings.json + models.json shapes
    fake_pi.lua                # Stand-in for `pi --mode rpc` used by e2e
  spec/pim/
    _smoke_spec.lua            # Sanity: every module loads + exports surface
    jsonl_spec.lua             # Newline-delimited JSON framing
    settings_editor_spec.lua   # In-place editor for `~/.pi/agent/settings.json`
    context_spec.lua           # File/range context + prompt formatting
    transcript_spec.lua        # Markdown + JSONL writes to state dir
    buffer_spec.lua            # Conversation buffer rendering + extmarks
    bridge_spec.lua            # Local TCP bridge + JSONL protocol
    rpc_spec.lua               # Subprocess lifecycle + on_event forwarding
    init_spec.lua              # Public API (setup, set_model, reload, etc.)
    e2e_spec.lua               # Full fake_pi → rpc → handle_event → buffer + transcript
```

## Running the suite

The runner needs plenary.nvim on your local pack path. If you don't have it
yet:

```bash
mkdir -p ~/.local/share/nvim/site/pack/local/start
git clone --depth 1 https://github.com/nvim-lua/plenary.nvim \
  ~/.local/share/nvim/site/pack/local/start/plenary.nvim
```

Then, from the repo root, run all specs (~5-15 s on a warm cache):

```bash
nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/spec {minimal_init = 'tests/minimal_init.lua'}"
```

To run a single spec (e.g. while iterating):

```bash
nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/spec/pim/settings_editor_spec.lua \
       {minimal_init = 'tests/minimal_init.lua'}"
```

Both commands exit non-zero on failure, so wire them straight into a CI step
or `make test`.

## How it's wired

* `tests/minimal_init.lua` adds this repo's `lua/` plus pleneary.nvim onto
  `runtimepath`, sets `vim.g.mapleader = " "` so `<leader>p*` mappings show
  up as ` p*` in `nvim_get_keymap`, and disables swap/shada. It does **not**
  source the user's real init.lua — the suite runs in isolation.
* Every spec's `before_each` resets `package.loaded["pim*"]` and stubs the
  sibling modules it doesn't want to exercise (e.g. `init_spec.lua`
  replaces `pim.bridge`/`pim.buffer`/`pim.rpc` so we never open a TCP socket
  or spawn a real subprocess from the public-API tests).
* `pim_config_dir` is set per-test through the public `setup({...})` knob
  so tests never touch the user's real `~/.pi/agent`.

## Catching real bugs

The suite caught and now locks in two regressions from the in-place settings
editor:

* `update_string_setting` no longer accidentally rewrites a key nested one
  level deep (e.g. inside a `theme` object).
* It strips trailing whitespace on the matched line (intentional
  normalization; if you want it preserved, the test is the place to flip
  the policy).

It also covers the `on_exit` race fix in `rpc.lua` (a late on_exit must not
clobber a newer `state.job_id`) under the "rpc race-condition fix" describe
block.
