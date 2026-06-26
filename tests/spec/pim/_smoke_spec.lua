-- Sanity check: every pim submodule loads and exports the expected surface.
describe("pim test scaffold", function()
  it("loads pim namespace", function()
    local pim = require("pim")
    assert.is_table(pim)
    assert.is_function(pim.setup)
    assert.is_function(pim.open)
    assert.is_function(pim.toggle)
    assert.is_function(pim.close)
    assert.is_function(pim.reload)
    assert.is_function(pim.pick_model)
    assert.is_function(pim.edit_model_config)
    assert.is_function(pim.set_model)
  end)

  it("loads every pim submodule without errors", function()
    for _, mod in ipairs({
      "pim.bridge",
      "pim.buffer",
      "pim.context",
      "pim.rpc",
      "pim.transcript",
      "pim.settings_editor",
      "pim.jsonl",
    }) do
      local ok, err = pcall(require, mod)
      assert.is_true(ok, "expected require('" .. mod .. "') to succeed: " .. tostring(err))
    end
  end)
end)
