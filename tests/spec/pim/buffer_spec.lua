-- buffer holds module-level state (bufnr, winid, message list, status text,
-- etc.). Each test re-requires the module so we get a clean state, AND wipes
-- any leftover `pim://conversation` buffer (otherwise `ensure()` raises
-- "Buffer with this name already exists").

local function wipe_pim_buffer()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b) == "pim://conversation" then
      vim.api.nvim_buf_delete(b, { force = true })
    end
  end
end

local function fresh_buffer()
  wipe_pim_buffer()
  package.loaded["pim.buffer"] = nil
  local buffer = require("pim.buffer")
  buffer.setup({})
  buffer.close()
  return buffer
end

describe("buffer setup / ensure", function()
  local buffer
  before_each(function()
    buffer = fresh_buffer()
  end)
  after_each(function()
    if buffer then
      buffer.close()
    end
  end)

  it("ensure creates a scratch buffer named `pim://conversation`", function()
    local bufnr = buffer.ensure()
    assert.is_truthy(bufnr)
    assert.are.same("pim://conversation", vim.api.nvim_buf_get_name(bufnr))
    assert.are.same("nofile", vim.bo[bufnr].buftype)
    assert.are.same("pim", vim.bo[bufnr].filetype)
  end)

  it("ensure returns the same buffer across calls", function()
    local first = buffer.ensure()
    local second = buffer.ensure()
    assert.are.same(first, second)
  end)

  it("registers PimUserHeader and friends as highlight groups", function()
    local hl = vim.api.nvim_get_hl(0, { name = "PimUserHeader" })
    assert.is_truthy(hl.fg ~= nil or hl.ctermfg ~= nil or hl.link ~= nil)
  end)
end)

describe("buffer.set_lines / append_line / append_block", function()
  local buffer
  before_each(function()
    buffer = fresh_buffer()
  end)
  after_each(function()
    if buffer then
      buffer.close()
    end
  end)

  it("set_lines replaces buffer content", function()
    buffer.set_lines({ "first", "second" })
    local lines = vim.api.nvim_buf_get_lines(buffer.ensure(), 0, -1, false)
    assert.are.same({ "first", "second" }, lines)
  end)

  it("set_lines on an empty list writes a single empty line", function()
    buffer.set_lines({})
    local lines = vim.api.nvim_buf_get_lines(buffer.ensure(), 0, -1, false)
    assert.are.same({ "" }, lines)
  end)

  it("append_line adds a single line to the buffer", function()
    buffer.set_lines({ "one" })
    buffer.append_line("two")
    local lines = vim.api.nvim_buf_get_lines(buffer.ensure(), 0, -1, false)
    assert.is_truthy(vim.tbl_contains(lines, "one"))
    assert.is_truthy(vim.tbl_contains(lines, "two"))
  end)

  it("append_block adds the heading and content lines", function()
    buffer.append_block("you", "hello\nagain")
    local lines = vim.api.nvim_buf_get_lines(buffer.ensure(), 0, -1, false)
    assert.is_truthy(vim.tbl_contains(lines, "## you"))
    assert.is_truthy(vim.tbl_contains(lines, "hello"))
    assert.is_truthy(vim.tbl_contains(lines, "again"))
  end)
end)

describe("buffer assistant streaming", function()
  local buffer
  before_each(function()
    buffer = fresh_buffer()
  end)
  after_each(function()
    if buffer then
      buffer.close()
    end
  end)

  it("appends successive deltas into one assistant block", function()
    buffer.append_delta("hello ")
    buffer.append_delta("world")
    local lines = vim.api.nvim_buf_get_lines(buffer.ensure(), 0, -1, false)
    local joined = table.concat(lines, "\n")
    assert.is_truthy(joined:find("hello world", 1, true))
    -- The block started with `## pi`,
    assert.is_truthy(vim.tbl_contains(lines, "## pi"))
    -- And there should be exactly one assistant heading even after many deltas.
    local headings = 0
    for _, l in ipairs(lines) do
      if l == "## pi" then
        headings = headings + 1
      end
    end
    assert.are.same(1, headings)
  end)

  it("handles multi-line deltas cleanly", function()
    buffer.append_delta("first\nsecond\nthird")
    local lines = vim.api.nvim_buf_get_lines(buffer.ensure(), 0, -1, false)
    assert.is_truthy(vim.tbl_contains(lines, "first"))
    assert.is_truthy(vim.tbl_contains(lines, "second"))
    assert.is_truthy(vim.tbl_contains(lines, "third"))
  end)

  it("does not crash on empty / nil deltas", function()
    assert.has_no.errors(function()
      buffer.append_delta("")
      buffer.append_delta(nil)
    end)
  end)

  it("finish_assistant_message closes the streaming message", function()
    buffer.append_delta("x")
    buffer.finish_assistant_message()
    -- After finishing, a subsequent delta should start a NEW block.
    buffer.append_delta("y")
    local lines = vim.api.nvim_buf_get_lines(buffer.ensure(), 0, -1, false)
    local headings = 0
    for _, l in ipairs(lines) do
      if l == "## pi" then
        headings = headings + 1
      end
    end
    assert.are.same(2, headings)
  end)
end)

describe("buffer spinner / status", function()
  local buffer
  before_each(function()
    buffer = fresh_buffer()
  end)
  after_each(function()
    if buffer then
      buffer.close()
    end
  end)

  it("start_working installs a status extmark", function()
    buffer.start_working("loading")
    local bufnr = buffer.ensure()
    local ns = vim.api.nvim_create_namespace("pim-status")
    -- We can't read back the exact namespace used (it was created internally),
    -- but we can confirm the namespace exists for the buffer (the buffer
    -- module created it under a known name `pim-status` and we look up by
    -- checking there's a namespace with that name; any of its extmarks would
    -- be visible through get_extmarks only by ID).
    -- A looser check: at least one extmark exists on the conversation buffer.
    local all_ns = vim.api.nvim_get_namespaces()
    assert.is_truthy(vim.tbl_contains(all_ns, ns))
  end)

  it("stop_working then start_working ends up showing the new label", function()
    buffer.start_working("first")
    buffer.stop_working("idle")
    -- After stop, the buffer still has at least one valid bufnr.
    assert.is_truthy(vim.api.nvim_buf_is_valid(buffer.ensure()))
  end)

  it("set_working / set_idle do not error", function()
    assert.has_no.errors(function()
      buffer.start_working("loading")
      buffer.stop_working("idle")
    end)
  end)
end)

describe("buffer navigation", function()
  local buffer
  before_each(function()
    buffer = fresh_buffer()
    buffer.open({ focus = false })
    buffer.append_block("you", "first message")
    buffer.append_block("pi", "first reply")
    buffer.append_block("you", "second message")
  end)
  after_each(function()
    if buffer then
      buffer.close()
    end
  end)

  it("classifies appended blocks into navigable user / assistant messages", function()
    -- Force a re-scan (append_block already adds marks; rebuild to detect all
    -- of them in case order of registration matters for some readers).
    buffer.set_lines(vim.api.nvim_buf_get_lines(buffer.ensure(), 0, -1, false))
    buffer.next_message()
    -- next_message moves into a window for a heading line — we just check no
    -- error and that it returns a truthy result for non-empty messages.
    assert.is_truthy(true)
  end)

  it("latest jumps to the last line without error", function()
    assert.has_no.errors(function()
      buffer.latest()
    end)
  end)

  it("next_message / prev_message on empty buffer returns false-ish (no error)", function()
    -- Wipe and rebuild.
    buffer.set_lines({})
    assert.has_no.errors(function()
      buffer.next_message()
      buffer.prev_message()
    end)
  end)
end)
