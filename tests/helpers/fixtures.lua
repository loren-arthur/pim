-- Sample inputs reused across specs (settings.json shapes, models.json, etc.).
local M = {}

function M.settings_basic()
  return [[{
  "defaultProvider": "anthropic",
  "defaultModel": "claude-sonnet-4-20250514",
  "theme": "dark"
}]]
end

function M.settings_two_keys_no_trailing_comma()
  return [[{
  "defaultProvider": "anthropic",
  "defaultModel": "claude-opus-4"
}]]
end

function M.settings_deeply_nested()
  return [[{
    "defaultProvider":"anthropic",
    "defaultModel":"opus",
    "tools": {
      bash = true,
      custom = { level = 3, items = { "a","b","c" } }
    }
}]]
end

function M.models_basic()
  return [[{
  "providers": {
    "anthropic": {
      "models": [
        { "id": "claude-sonnet-4-20250514", "name": "Claude Sonnet 4" },
        { "id": "claude-opus-4-20250514",  "name": "Claude Opus 4" }
      ]
    },
    "openai": {
      "models": [
        { "id": "gpt-5", "name": "GPT-5" }
      ]
    }
  }
}]]
end

return M
