-- transcript writes files under `state.dir`. Each test uses a fresh tmpdir so
-- cross-test state cannot leak.

local function tmpdir_setup()
  local dir = vim.fn.tempname()
  require("pim.transcript").setup({ dir = dir })
  return dir
end

local function cleanup(dir)
  vim.fn.delete(dir, "rf")
end

describe("transcript.setup", function()
  local dir
  before_each(function()
    package.loaded["pim.transcript"] = nil
  end)
  after_each(function()
    if dir then
      cleanup(dir)
      dir = nil
    end
  end)

  it("creates the directory if it does not exist", function()
    dir = tmpdir_setup()
    assert.are.same(1, vim.fn.isdirectory(dir))
  end)

  it("accepts an existing directory without failing", function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local transcript = require("pim.transcript")
    assert.has_no.errors(function()
      transcript.setup({ dir = dir })
    end)
  end)
end)

describe("transcript.attach_session", function()
  local dir
  local transcript
  before_each(function()
    package.loaded["pim.transcript"] = nil
    dir = tmpdir_setup()
    transcript = require("pim.transcript")
  end)
  after_each(function()
    if dir then
      cleanup(dir)
      dir = nil
    end
  end)

  it("writes a header markdown file on first attach", function()
    transcript.attach_session({
      sessionId = "abc123",
      sessionFile = "/tmp/sess.jsonl",
      sessionName = "Test session",
    })
    local lines = vim.fn.readfile(dir .. "/abc123.md")
    assert.are.same("# pim conversation", lines[1])
    assert.is_truthy(vim.tbl_contains(lines, "- Session ID: abc123"))
    assert.is_truthy(vim.tbl_contains(lines, "- Session file: /tmp/sess.jsonl"))
    assert.is_truthy(vim.tbl_contains(lines, "- Session name: Test session"))
  end)

  it("does not overwite the header on subsequent attach", function()
    transcript.attach_session({ sessionId = "x", sessionFile = "/x" })
    transcript.append_block("you", "hello")
    transcript.attach_session({ sessionId = "x", sessionFile = "/x" })
    local lines = vim.fn.readfile(dir .. "/x.md")
    -- The header should still exist exactly once.
    local count = 0
    for _, line in ipairs(lines) do
      if line == "# pim conversation" then
        count = count + 1
      end
    end
    assert.are.same(1, count)
  end)

  it("sanitizes the session id into a safe filename", function()
    transcript.attach_session({ sessionId = "../with spaces and /slashes" })
    -- The file path should be inside `dir`, not above it.
    local p = transcript.paths()
    assert.is_truthy(p.markdown:find(dir, 1, true) == 1)
  end)

  it("switches the active session between calls", function()
    transcript.attach_session({ sessionId = "a" })
    transcript.append_block("you", "first")
    transcript.attach_session({ sessionId = "b" })
    transcript.append_block("you", "second")

    local a_lines = vim.fn.readfile(dir .. "/a.md")
    local b_lines = vim.fn.readfile(dir .. "/b.md")
    assert.is_truthy(vim.tbl_contains(a_lines, "first"))
    assert.is_false(vim.tbl_contains(a_lines, "second"))
    assert.is_truthy(vim.tbl_contains(b_lines, "second"))
    assert.is_false(vim.tbl_contains(b_lines, "first"))
  end)
end)

describe("transcript.append_*", function()
  local dir
  local transcript
  before_each(function()
    package.loaded["pim.transcript"] = nil
    dir = tmpdir_setup()
    transcript = require("pim.transcript")
    transcript.attach_session({ sessionId = "s" })
  end)
  after_each(function()
    if dir then
      cleanup(dir)
      dir = nil
    end
  end)

  it("append_markdown writes verbatim to the .md file", function()
    transcript.append_markdown("hello\n")
    local lines = vim.fn.readfile(dir .. "/s.md")
    assert.is_truthy(vim.tbl_contains(lines, "hello"))
  end)

  it("append_block adds a `## title` heading and the body", function()
    transcript.append_block("you", "msg")
    local lines = vim.fn.readfile(dir .. "/s.md")
    assert.is_truthy(vim.tbl_contains(lines, "## you"))
    assert.is_truthy(vim.tbl_contains(lines, "msg"))
  end)

  it("append_event writes one JSON line per call to .jsonl", function()
    transcript.append_event({ type = "agent_start" })
    transcript.append_event({ type = "agent_end" })
    local lines = vim.fn.readfile(dir .. "/s.jsonl")
    assert.are.same(2, #lines)
    assert.are.same({ type = "agent_start" }, vim.json.decode(lines[1]))
    assert.are.same({ type = "agent_end" }, vim.json.decode(lines[2]))
  end)

  it("append_event swallows events that fail JSON encoding", function()
    -- A circular reference would fail vim.json.encode.
    local bad = {}
    bad.self = bad
    assert.has_no.errors(function()
      transcript.append_event(bad)
    end)
    -- jsonl file should be empty (no line written).
    local path = dir .. "/s.jsonl"
    if vim.fn.filereadable(path) == 1 then
      local lines = vim.fn.readfile(path)
      assert.are.same(0, #lines)
    end
  end)
end)

describe("transcript.read_markdown_lines", function()
  local dir
  local transcript
  before_each(function()
    package.loaded["pim.transcript"] = nil
    dir = tmpdir_setup()
    transcript = require("pim.transcript")
    transcript.attach_session({ sessionId = "r" })
  end)
  after_each(function()
    if dir then
      cleanup(dir)
      dir = nil
    end
  end)

  it("returns the full markdown file as a list of lines", function()
    transcript.append_markdown("line-a\nline-b\n")
    local lines = transcript.read_markdown_lines()
    assert.is_truthy(vim.tbl_contains(lines, "line-a"))
    assert.is_truthy(vim.tbl_contains(lines, "line-b"))
  end)

  it("strips a single trailing blank line", function()
    transcript.append_markdown("only\n")
    local lines = transcript.read_markdown_lines()
    assert.are.same("only", lines[#lines])
  end)

  it("returns an empty list when no attach has happened and no file exists", function()
    package.loaded["pim.transcript"] = nil
    dir = tmpdir_setup()
    local fresh = require("pim.transcript")
    -- ensure_current creates a default session; the file may not exist yet.
    local lines = fresh.read_markdown_lines()
    assert.is_table(lines)
  end)
end)

describe("transcript.paths", function()
  local dir
  local transcript
  before_each(function()
    package.loaded["pim.transcript"] = nil
    dir = tmpdir_setup()
    transcript = require("pim.transcript")
  end)
  after_each(function()
    if dir then
      cleanup(dir)
      dir = nil
    end
  end)

  it("returns the markdown and jsonl file paths and the session table", function()
    transcript.attach_session({ sessionId = "p" })
    local p = transcript.paths()
    assert.are.same(dir .. "/p.md", p.markdown)
    assert.are.same(dir .. "/p.jsonl", p.jsonl)
    assert.are.same("p", p.session.sessionId)
  end)
end)
