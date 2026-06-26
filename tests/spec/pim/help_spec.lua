local help = require("pim.help")

-- Flatten the catalog into a set of base command names (":PimOpen" etc.,
-- stripped of any "[args]" / "(visual)" suffixes).
local function catalog_commands()
  local set = {}
  for _, group in ipairs(help.catalog) do
    for _, item in ipairs(group.items) do
      local name = item.cmd:match("^(:%a+)")
      if name then
        set[name] = true
      end
    end
  end
  return set
end

-- Parse plugin/pim.lua for every registered user command.
local function registered_commands()
  local plugin_path = vim.fn.fnamemodify(
    debug.getinfo(1, "S").source:sub(2), ":p:h:h:h:h"
  ) .. "/plugin/pim.lua"
  assert(vim.fn.filereadable(plugin_path) == 1, "could not read " .. plugin_path)
  local set = {}
  for _, line in ipairs(vim.fn.readfile(plugin_path)) do
    local name = line:match('nvim_create_user_command%("(%a+)"')
    if name then
      set[":" .. name] = true
    end
  end
  return set
end

describe("pim.help", function()
  it("render includes a header, the prefix note, and a known mapping", function()
    local lines = help.render("<leader>p")
    local text = table.concat(lines, "\n")
    assert.is_truthy(text:find("# pim commands", 1, true))
    assert.is_truthy(text:find("<leader>p` prefix", 1, true))
    assert.is_truthy(text:find(":PimToggle", 1, true))
    assert.is_truthy(text:find("<leader>pp", 1, true))
    assert.is_truthy(text:find(":PimSendComments", 1, true))
  end)

  it("notes when mappings are disabled", function()
    local text = table.concat(help.render(nil), "\n")
    assert.is_truthy(text:find("Default mappings are disabled", 1, true))
  end)

  it("documents every registered Pim user command", function()
    local cataloged = catalog_commands()
    local registered = registered_commands()
    local missing = {}
    for cmd in pairs(registered) do
      if not cataloged[cmd] then
        table.insert(missing, cmd)
      end
    end
    table.sort(missing)
    assert.are.same({}, missing, "help catalog is missing: " .. table.concat(missing, ", "))
  end)
end)
