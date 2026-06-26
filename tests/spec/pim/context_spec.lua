local context = require("pim.context")

-- Each test creates a fresh scratch buffer; teardown deletes it so cleanup
-- doesn't leak into other tests.
local function fresh_named_buffer(name, lines)
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(bufnr, name)
  if lines then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  end
  return bufnr
end

describe("context.range", function()
  local bufnr
  local diag_ns
  before_each(function()
    bufnr = fresh_named_buffer("/tmp/pim-test-context.lua", {
      "line 1",
      "line 2",
      "line 3",
      "line 4",
    })
    diag_ns = vim.api.nvim_create_namespace("pim-test-diag-r")
  end)
  after_each(function()
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("returns the file path, line range, and selected text", function()
    local ctx = context.range({ bufnr = bufnr, line1 = 2, line2 = 3 })
    assert.are.same("/tmp/pim-test-context.lua", ctx.file)
    assert.are.same({ start = 2, finish = 3 }, ctx.range)
    assert.are.same("line 2\nline 3", ctx.text)
  end)

  it("joins multiple lines with newlines in `text`", function()
    local ctx = context.range({ bufnr = bufnr, line1 = 1, line2 = 4 })
    assert.are.same("line 1\nline 2\nline 3\nline 4", ctx.text)
  end)

  it("normalizes line1 > line2 by swapping", function()
    local ctx = context.range({ bufnr = bufnr, line1 = 3, line2 = 1 })
    assert.are.same({ start = 1, finish = 3 }, ctx.range)
    assert.are.same("line 1\nline 2\nline 3", ctx.text)
  end)

  it("returns no diagnostics when none are present", function()
    local ctx = context.range({ bufnr = bufnr, line1 = 1, line2 = 4 })
    assert.are.same({}, ctx.diagnostics)
  end)

  it("filters diagnostics to only those within the line range", function()
    vim.diagnostic.set(diag_ns, bufnr, {
      { lnum = 0, col = 0, message = "above the range",  severity = vim.diagnostic.severity.ERROR },
      { lnum = 1, col = 0, message = "inside the range", severity = vim.diagnostic.severity.WARN  },
      { lnum = 2, col = 0, message = "below the range",  severity = vim.diagnostic.severity.ERROR },
    })
    -- Range that covers only line 2 (line1=line2=2), so only the middle diag
    -- is "inside" the range; the above and below diagnostics are filtered out.
    local ctx = context.range({ bufnr = bufnr, line1 = 2, line2 = 2 })
    assert.are.same(1, #ctx.diagnostics)
    assert.are.same("inside the range", ctx.diagnostics[1].message)
    assert.are.same(2, ctx.diagnostics[1].line)
    assert.are.same(vim.diagnostic.severity.WARN, ctx.diagnostics[1].severity)
  end)

  it("returns nil file when the buffer has no name", function()
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
    bufnr = vim.api.nvim_create_buf(true, false)
    local ctx = context.range({ bufnr = bufnr, line1 = 1, line2 = 1 })
    assert.is_nil(ctx.file)
  end)

  it("single-line range uses same start and finish", function()
    local ctx = context.range({ bufnr = bufnr, line1 = 2, line2 = 2 })
    assert.are.same({ start = 2, finish = 2 }, ctx.range)
  end)
end)

describe("context.current_buffer", function()
  local bufnr
  after_each(function()
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("covers the entire buffer (1..line_count)", function()
    bufnr = fresh_named_buffer("/tmp/pim-test-current.lua", {
      "alpha", "beta", "gamma",
    })
    vim.api.nvim_set_current_buf(bufnr)
    local ctx = context.current_buffer()
    assert.are.same({ start = 1, finish = 3 }, ctx.range)
    assert.are.same("alpha\nbeta\ngamma", ctx.text)
  end)
end)

describe("context.prompt_for_range", function()
  it("includes file path, range, and the selected text in a code fence", function()
    local prompt = context.prompt_for_range(nil, {
      file = "/tmp/foo.lua",
      range = { start = 5, finish = 7 },
      text = "x = 1\ny = 2",
      diagnostics = {},
    })
    assert.is_truthy(prompt:find("/tmp/foo.lua", 1, true))
    assert.is_truthy(prompt:find("5-7", 1, true))
    assert.is_truthy(prompt:find("x = 1", 1, true))
    assert.is_truthy(prompt:find("y = 2", 1, true))
    assert.is_truthy(prompt:find("```", 1, true))
  end)

  it("uses a single line number when start == finish", function()
    local prompt = context.prompt_for_range(nil, {
      file = "f.lua",
      range = { start = 9, finish = 9 },
      text = "x",
      diagnostics = {},
    })
    assert.is_truthy(prompt:find("Range: 9\n", 1, true))
    assert.is_nil(prompt:find("Range: 9-9", 1, true))
  end)

  it("falls back to `[No file name]` when file is nil", function()
    local prompt = context.prompt_for_range(nil, {
      file = nil,
      range = { start = 1, finish = 1 },
      text = "",
      diagnostics = {},
    })
    assert.is_truthy(prompt:find("[No file name]", 1, true))
  end)

  it("includes a `User comment/question:` section when provided", function()
    local prompt = context.prompt_for_range("why is this slow?", {
      file = "x", range = { start = 1, finish = 1 }, text = "", diagnostics = {},
    })
    assert.is_truthy(prompt:find("User comment/question:", 1, true))
    assert.is_truthy(prompt:find("why is this slow?", 1, true))
    assert.is_nil(prompt:find("Please use this editor context", 1, true))
  end)

  it("uses the editor-context placeholder when no comment is provided", function()
    local prompt = context.prompt_for_range("", {
      file = "x", range = { start = 1, finish = 1 }, text = "", diagnostics = {},
    })
    assert.is_truthy(prompt:find("Please use this editor context", 1, true))
  end)

  it("renders a `Diagnostics in range:` section with each diagnostic", function()
    local prompt = context.prompt_for_range(nil, {
      file = "x", range = { start = 1, finish = 1 }, text = "",
      diagnostics = {
        { line = 7, message = "unused variable `foo`", source = "lua_ls" },
        { line = 12, message = "missing return" },
      },
    })
    assert.is_truthy(prompt:find("Diagnostics in range:", 1, true))
    assert.is_truthy(prompt:find("line 7: unused variable `foo` [lua_ls]", 1, true))
    assert.is_truthy(prompt:find("line 12: missing return", 1, true))
  end)

  it("omits the diagnostics section when there are none", function()
    local prompt = context.prompt_for_range(nil, {
      file = "x", range = { start = 1, finish = 1 }, text = "", diagnostics = {},
    })
    assert.is_nil(prompt:find("Diagnostics in range:", 1, true))
  end)
end)
