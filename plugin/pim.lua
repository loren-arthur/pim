if vim.g.loaded_pim == 1 then
  return
end
vim.g.loaded_pim = 1

local function pim()
  return require("pim")
end

vim.api.nvim_create_user_command("PimOpen", function()
  pim().open()
end, { desc = "Open pim conversation pane" })

vim.api.nvim_create_user_command("PimClose", function()
  pim().close()
end, { desc = "Close pim conversation pane" })

vim.api.nvim_create_user_command("PimToggle", function()
  pim().toggle()
end, { desc = "Toggle pim conversation pane" })

vim.api.nvim_create_user_command("PimNewSession", function(opts)
  pim().new_session(opts.args)
end, {
  nargs = "*",
  desc = "Start a fresh pi session in the current pim RPC process",
})

vim.api.nvim_create_user_command("PimOpenFresh", function(opts)
  pim().open_fresh(opts.args)
end, {
  nargs = "*",
  desc = "Open pim and immediately start a fresh pi session",
})

vim.api.nvim_create_user_command("PimOpenSelect", function()
  pim().open_select()
end, { desc = "Open pim with a per-directory session selector" })

vim.api.nvim_create_user_command("PimSessionInfo", function()
  pim().session_info()
end, { desc = "Show current and workspace-pinned pim session info" })

vim.api.nvim_create_user_command("PimForgetSession", function()
  pim().forget_workspace_session()
end, { desc = "Forget the workspace-pinned pim session" })

vim.api.nvim_create_user_command("PimSend", function(opts)
  pim().send(opts.args)
end, {
  nargs = "*",
  desc = "Send a prompt to pi",
})

vim.api.nvim_create_user_command("PimSendSelection", function(opts)
  pim().send_selection({
    line1 = opts.line1,
    line2 = opts.line2,
    comment = opts.args,
  })
end, {
  nargs = "*",
  range = true,
  desc = "Send selected/ranged text with an optional comment to pi",
})

vim.api.nvim_create_user_command("PimCompose", function()
  pim().compose()
end, { desc = "Open a floating pim prompt composer" })

vim.api.nvim_create_user_command("PimComposeSelection", function(opts)
  pim().compose_selection({
    line1 = opts.line1,
    line2 = opts.line2,
  })
end, {
  range = true,
  desc = "Open a floating pim composer for selected/ranged text",
})

vim.api.nvim_create_user_command("PimComment", function(opts)
  pim().comment({
    line1 = opts.range > 0 and opts.line1 or nil,
    line2 = opts.range > 0 and opts.line2 or nil,
    comment = opts.args,
  })
end, {
  nargs = "*",
  range = true,
  desc = "Attach an inline comment to the current line/range",
})

vim.api.nvim_create_user_command("PimSendComments", function(opts)
  pim().send_comments({ intro = opts.args ~= "" and opts.args or nil })
end, {
  nargs = "*",
  desc = "Send all pending inline comments to pi as one structured message",
})

vim.api.nvim_create_user_command("PimComments", function()
  pim().list_comments()
end, { desc = "List pending pim inline comments" })

vim.api.nvim_create_user_command("PimClearComments", function()
  pim().clear_comments()
end, { desc = "Clear all pending pim inline comments" })

vim.api.nvim_create_user_command("PimSteer", function(opts)
  pim().steer(opts.args)
end, {
  nargs = "*",
  desc = "Queue a steering message for pi while it is processing",
})

vim.api.nvim_create_user_command("PimFollowUp", function(opts)
  pim().follow_up(opts.args)
end, {
  nargs = "*",
  desc = "Queue a follow-up message for pi after current work finishes",
})

vim.api.nvim_create_user_command("PimTranscript", function()
  pim().open_transcript()
end, { desc = "Open the durable pim markdown transcript" })

vim.api.nvim_create_user_command("PimTranscriptPath", function()
  local paths = pim().transcript_paths()
  print(paths.markdown)
end, { desc = "Print the durable pim markdown transcript path" })

vim.api.nvim_create_user_command("PimBridgeInfo", function()
  local info = pim().bridge_info()
  print("pim bridge port=" .. tostring(info.port))
end, { desc = "Print pim Neovim bridge info" })

vim.api.nvim_create_user_command("PimClearHighlights", function()
  pim().clear_highlights()
end, { desc = "Clear pim-created Neovim highlights" })

vim.api.nvim_create_user_command("PimNextMessage", function()
  pim().next_message()
end, { desc = "Jump to next pim conversation message" })

vim.api.nvim_create_user_command("PimPrevMessage", function()
  pim().prev_message()
end, { desc = "Jump to previous pim conversation message" })

vim.api.nvim_create_user_command("PimLatest", function()
  pim().latest()
end, { desc = "Jump to latest pim conversation line" })

vim.api.nvim_create_user_command("PimAbort", function()
  pim().abort()
end, { desc = "Abort the current pi operation" })

vim.api.nvim_create_user_command("PimStop", function()
  pim().stop()
end, { desc = "Stop the pi RPC process" })

vim.api.nvim_create_user_command("PimModel", function()
  pim().pick_model()
end, { desc = "Pick the pi model interactively, then reload" })

vim.api.nvim_create_user_command("PimModelEdit", function()
  pim().edit_model_config()
end, { desc = "Open pi's model settings file for manual editing" })

vim.api.nvim_create_user_command("PimReload", function()
  pim().reload()
end, { desc = "Restart pi (resuming the session) to apply config/model changes" })

vim.api.nvim_create_user_command("PimCompact", function(opts)
  pim().compact(opts.args)
end, {
  nargs = "*",
  desc = "Compact conversation context; optional custom instructions focus the summary",
})

vim.api.nvim_create_user_command("PimAutoCompact", function(opts)
  local arg = opts.args:lower()
  local enabled
  if arg == "" or arg == "toggle" then
    enabled = nil
  elseif arg == "on" or arg == "true" or arg == "1" then
    enabled = true
  elseif arg == "off" or arg == "false" or arg == "0" then
    enabled = false
  else
    vim.notify("pim: PimAutoCompact expects on/off/toggle, got " .. opts.args, vim.log.levels.WARN)
    return
  end
  pim().set_auto_compaction(enabled)
end, {
  nargs = "?",
  complete = function() return { "on", "off", "toggle" } end,
  desc = "Toggle or set pi automatic context compaction",
})

vim.api.nvim_create_user_command("PimHelp", function()
  pim().help()
end, { desc = "Show a buffer listing all pim commands and their usage" })
