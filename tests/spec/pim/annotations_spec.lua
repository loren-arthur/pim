local annotations = require("pim.annotations")
local context = require("pim.context")

local function fresh_named_buffer(name, lines)
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(bufnr, name)
  if lines then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  end
  return bufnr
end

describe("pim.annotations", function()
  local bufnr
  before_each(function()
    annotations.clear()
    bufnr = fresh_named_buffer("/tmp/pim-test-annotations.lua", {
      "line 1",
      "line 2",
      "line 3",
      "line 4",
    })
  end)
  after_each(function()
    annotations.clear()
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("add records a comment over a range and list resolves it", function()
    annotations.add("fix this", { bufnr = bufnr, line1 = 2, line2 = 3 })
    local list = annotations.list()
    assert.are.equal(1, #list)
    assert.are.equal("fix this", list[1].comment)
    assert.are.equal(2, list[1].range.start)
    assert.are.equal(3, list[1].range.finish)
    assert.are.equal("line 2\nline 3", list[1].text)
    assert.is_truthy(list[1].file:find("pim%-test%-annotations%.lua$"))
  end)

  it("add ignores empty comments", function()
    assert.is_nil(annotations.add("", { bufnr = bufnr, line1 = 1 }))
    assert.are.equal(0, annotations.count())
  end)

  it("ranges track edits via extmarks", function()
    annotations.add("note", { bufnr = bufnr, line1 = 3, line2 = 3 })
    -- Insert two lines above the annotated line; it should shift down.
    vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "new a", "new b" })
    local list = annotations.list()
    assert.are.equal(1, #list)
    assert.are.equal(5, list[1].range.start)
    assert.are.equal("line 3", list[1].text)
  end)

  it("clear with a bufnr removes only that buffer's annotations", function()
    local other = fresh_named_buffer("/tmp/pim-test-annotations-2.lua", { "x", "y" })
    annotations.add("a", { bufnr = bufnr, line1 = 1 })
    annotations.add("b", { bufnr = other, line1 = 1 })
    annotations.clear(bufnr)
    local list = annotations.list()
    assert.are.equal(1, #list)
    assert.are.equal("b", list[1].comment)
    vim.api.nvim_buf_delete(other, { force = true })
  end)

  it("prunes annotations from deleted buffers", function()
    local other = fresh_named_buffer("/tmp/pim-test-annotations-3.lua", { "x" })
    annotations.add("gone", { bufnr = other, line1 = 1 })
    vim.api.nvim_buf_delete(other, { force = true })
    assert.are.equal(0, annotations.count())
  end)
end)

describe("context.prompt_for_annotations", function()
  it("renders each annotation with file, range, text, and comment", function()
    local prompt = context.prompt_for_annotations({
      {
        file = "/tmp/a.lua",
        range = { start = 2, finish = 3 },
        text = "local x = 1",
        comment = "rename x",
      },
    }, "overall cleanup")
    assert.is_truthy(prompt:find("Overall request:", 1, true))
    assert.is_truthy(prompt:find("overall cleanup", 1, true))
    assert.is_truthy(prompt:find("Comment 1 — /tmp/a.lua:2-3", 1, true))
    assert.is_truthy(prompt:find("local x = 1", 1, true))
    assert.is_truthy(prompt:find("Comment: rename x", 1, true))
  end)

  it("omits the overall request when no intro is given", function()
    local prompt = context.prompt_for_annotations({
      { file = "/tmp/a.lua", range = { start = 5, finish = 5 }, text = "y", comment = "z" },
    })
    assert.is_nil(prompt:find("Overall request:", 1, true))
    assert.is_truthy(prompt:find("Comment 1 — /tmp/a.lua:5", 1, true))
  end)
end)
