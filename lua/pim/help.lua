-- pim help buffer: a single source-of-truth catalog of user commands, their
-- default mappings, and short usage notes, rendered into a scratch buffer via
-- :PimHelp. Keep this catalog in sync when adding/removing commands.

local M = {}

-- Each group has a title and items. Item fields:
--   cmd     command form shown to the user (with [args] where relevant)
--   desc    one-line description
--   map     optional { suffix = "x", visual = false } default <prefix> mapping
M.catalog = {
  {
    title = "Conversation",
    items = {
      { cmd = ":PimOpen", desc = "Open the conversation pane" },
      { cmd = ":PimToggle", map = { suffix = "p" }, desc = "Toggle the conversation pane" },
      { cmd = ":PimClose", desc = "Close the conversation pane" },
      { cmd = ":PimSend [text]", map = { suffix = "s" }, desc = "Send a prompt; no text opens the composer" },
      { cmd = ":PimSendSelection [text]", map = { suffix = "s", visual = true }, desc = "Send selection/range with optional comment" },
      { cmd = ":PimCompose", map = { suffix = "c" }, desc = "Floating composer for a longer prompt" },
      { cmd = ":PimComposeSelection", map = { suffix = "c", visual = true }, desc = "Composer seeded with the selection/range" },
      { cmd = ":PimSteer [text]", map = { suffix = "S" }, desc = "Queue a steering message while pi is working" },
      { cmd = ":PimFollowUp [text]", map = { suffix = "f" }, desc = "Queue a follow-up for after current work" },
      { cmd = ":PimAbort", map = { suffix = "a" }, desc = "Abort the current pi operation" },
      { cmd = ":PimStop", map = { suffix = "x" }, desc = "Stop the pi RPC process" },
    },
  },
  {
    title = "Inline comments",
    items = {
      { cmd = ":PimComment [text]", map = { suffix = "i" }, desc = "Attach an inline comment to the current line" },
      { cmd = ":PimComment", map = { suffix = "i", visual = true }, desc = "Attach an inline comment to the selection/range" },
      { cmd = ":PimComments", desc = "List pending inline comments" },
      { cmd = ":PimSendComments [note]", map = { suffix = "I" }, desc = "Send all pending comments as one structured message" },
      { cmd = ":PimClearComments", map = { suffix = "C" }, desc = "Clear all pending inline comments" },
    },
  },
  {
    title = "Sessions",
    items = {
      { cmd = ":PimOpenSelect", desc = "Open with a per-directory session selector" },
      { cmd = ":PimNewSession [name]", desc = "Start a fresh session in the running pi process" },
      { cmd = ":PimOpenFresh [name]", desc = "Open and immediately start a fresh session" },
      { cmd = ":PimSessionInfo", desc = "Show current and workspace-pinned session info" },
      { cmd = ":PimForgetSession", desc = "Forget the workspace-pinned session" },
    },
  },
  {
    title = "Navigation",
    items = {
      { cmd = ":PimNextMessage", desc = "Jump to the next message" },
      { cmd = ":PimPrevMessage", desc = "Jump to the previous message" },
      { cmd = ":PimLatest", desc = "Jump to the latest line" },
    },
  },
  {
    title = "Model & config",
    items = {
      { cmd = ":PimModel", map = { suffix = "m" }, desc = "Pick the pi model interactively, then reload" },
      { cmd = ":PimModelEdit", desc = "Open pi's model settings file for manual editing" },
      { cmd = ":PimReload", map = { suffix = "r" }, desc = "Restart pi (resuming) to apply config/model changes" },
    },
  },
  {
    title = "Highlights, transcript & diagnostics",
    items = {
      { cmd = ":PimClearHighlights", desc = "Clear pim-created Neovim highlights" },
      { cmd = ":PimTranscript", map = { suffix = "t" }, desc = "Open the durable markdown transcript" },
      { cmd = ":PimTranscriptPath", desc = "Print the durable transcript file path" },
      { cmd = ":PimBridgeInfo", desc = "Print the Neovim bridge port" },
      { cmd = ":PimHelp", desc = "Show this help buffer" },
    },
  },
}

local function mapping_label(map, prefix)
  if not map or not prefix then
    return ""
  end
  local label = prefix .. map.suffix
  if map.visual then
    label = label .. " (visual)"
  end
  return label
end

-- Build the help buffer lines. `prefix` is the configured keymap prefix (e.g.
-- "<leader>p") or nil when mappings are disabled.
function M.render(prefix)
  -- Measure columns so the command / mapping / description align.
  local cmd_w, map_w = 0, 0
  for _, group in ipairs(M.catalog) do
    for _, item in ipairs(group.items) do
      cmd_w = math.max(cmd_w, #item.cmd)
      map_w = math.max(map_w, #mapping_label(item.map, prefix))
    end
  end

  local lines = { "# pim commands", "" }
  if prefix then
    table.insert(lines, "Default mappings use the `" .. prefix .. "` prefix (configurable via `keymaps.prefix`).")
  else
    table.insert(lines, "Default mappings are disabled (`keymaps = false`).")
  end
  table.insert(lines, "Press `q` to close this buffer.")

  for _, group in ipairs(M.catalog) do
    table.insert(lines, "")
    table.insert(lines, "## " .. group.title)
    table.insert(lines, "")
    for _, item in ipairs(group.items) do
      local cmd = item.cmd .. string.rep(" ", cmd_w - #item.cmd)
      local map = mapping_label(item.map, prefix)
      map = map .. string.rep(" ", map_w - #map)
      local row = "  " .. cmd .. "  " .. map .. "  " .. item.desc
      table.insert(lines, (row:gsub("%s+$", "")))
    end
  end

  return lines
end

-- Open (or refocus) the help buffer.
function M.open(prefix)
  local existing
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b):match("pim://help$") then
      existing = b
      break
    end
  end

  local bufnr = existing or vim.api.nvim_create_buf(false, true)
  if not existing then
    vim.api.nvim_buf_set_name(bufnr, "pim://help")
  end

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, M.render(prefix))
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "markdown"
  vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = bufnr, silent = true, desc = "pim close help" })

  vim.cmd("botright vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, bufnr)
  vim.api.nvim_win_set_width(win, math.min(96, math.max(60, math.floor(vim.o.columns * 0.5))))
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  return bufnr
end

return M
