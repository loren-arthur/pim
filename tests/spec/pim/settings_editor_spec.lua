local editor = require("pim.settings_editor")

describe("settings_editor.update_string_setting", function()
  it("replaces existing top-level key, preserving indent and trailing comma", function()
    local input = [[{
  "defaultProvider": "anthropic",
  "defaultModel": "claude-sonnet-4-20250514",
}]]
    local out, found = editor.update_string_setting(input, "defaultProvider", "openai")
    assert.is_true(found)
    assert.are.same([[{
  "defaultProvider": "openai",
  "defaultModel": "claude-sonnet-4-20250514",
}]], out)
  end)

  it("replaces last key (no trailing comma) without adding one", function()
    local input = [[{
  "defaultProvider": "anthropic",
  "defaultModel": "claude-opus-4"
}]]
    local out, found = editor.update_string_setting(input, "defaultModel", "gpt-5")
    assert.is_true(found)
    assert.are.same([[{
  "defaultProvider": "anthropic",
  "defaultModel": "gpt-5"
}]], out)
  end)

  it("preserves nested objects untouched", function()
    local input = [[{
    "defaultProvider":"anthropic",
    "tools": {
      bash = true,
      custom = { level = 3, items = { "a","b","c" } }
    }
}]]
    local out, found = editor.update_string_setting(input, "defaultProvider", "openai")
    assert.is_true(found)
    assert.are.same([[{
    "defaultProvider": "openai",
    "tools": {
      bash = true,
      custom = { level = 3, items = { "a","b","c" } }
    }
}]], out)
  end)

  it("returns text unchanged and false when the key is not present", function()
    local input = [[{
  "theme": "dark"
}]]
    local out, found = editor.update_string_setting(input, "defaultProvider", "openai")
    assert.is_false(found)
    assert.are.same(input, out)
  end)

  it("does not match nested object keys (only top-level)", function()
    local input = [[{
  "theme": {
    "defaultProvider": "anthropic"
  }
}]]
    local out, found = editor.update_string_setting(input, "defaultProvider", "openai")
    assert.is_false(found)
    assert.are.same(input, out)
  end)

  it("strips trailing whitespace on the matched line", function()
    local input = "{\n    \"defaultProvider\": \"anthropic\",   \n}"
    local out, found = editor.update_string_setting(input, "defaultProvider", "openai")
    assert.is_true(found)
    -- Trailing spaces are intentional whitespace normalization; if you want
    -- them preserved, file an issue and we will revisit.
    assert.are.same("{\n    \"defaultProvider\": \"openai\",\n}", out)
  end)

  it("JSON-encodes the inserted value (escapes inner quotes)", function()
    local input = [[{
  "model": "claude"
}]]
    local out, found = editor.update_string_setting(input, "model", 'with "quotes"')
    assert.is_true(found)
    -- vim.json.encode wraps in quotes and escapes the inner ones.
    assert.is_truthy(out:find('"with \\"quotes\\""', 1, true))
  end)
end)

describe("settings_editor.insert_string_setting", function()
  it("inserts before the closing brace, borrowing indent", function()
    local input = [[{
  "defaultProvider": "anthropic",
  "theme": "dark"
}]]
    local out, found = editor.insert_string_setting(input, "defaultModel", "claude")
    assert.is_true(found)
    assert.are.same([[{
  "defaultProvider": "anthropic",
  "theme": "dark",
  "defaultModel": "claude",
}]], out)
  end)

  it("adds a trailing comma to the previously-last sibling", function()
    local input = [[{
  "defaultModel": "claude",
  "theme": "dark"
}]]
    local out = input
    local _, pfound = editor.update_string_setting(out, "defaultProvider", "openai")
    assert.is_false(pfound)
    out, _ = editor.insert_string_setting(out, "defaultProvider", "openai")
    assert.are.same([[{
  "defaultModel": "claude",
  "theme": "dark",
  "defaultProvider": "openai",
}]], out)
  end)

  it("handles a single-line empty `{}`", function()
    local out, found = editor.insert_string_setting("{}", "defaultModel", "gpt-5")
    assert.is_true(found)
    assert.are.same("{\n  " .. vim.json.encode("defaultModel") .. ": " .. vim.json.encode("gpt-5") .. "\n}", out)
  end)

  it("returns text unchanged and false when no closing brace is found", function()
    local _, found = editor.insert_string_setting("not json", "model", "x")
    assert.is_false(found)
  end)

  it("picks up the user's indent style from existing keys", function()
    local input = [[{
    "theme": "dark"
}]]
    local out = editor.insert_string_setting(input, "defaultProvider", "openai")
    assert.are.same([[{
    "theme": "dark",
    "defaultProvider": "openai",
}]], out)
  end)

  it("adds a comma to the nested closing brace when inserting a top-level sibling", function()
    local input = [[{
    "tools": {
      bash = true
    }
}]]
    local out = editor.insert_string_setting(input, "defaultProvider", "openai")
    assert.are.same([[{
    "tools": {
      bash = true
    },
    "defaultProvider": "openai",
}]], out)
  end)
end)
