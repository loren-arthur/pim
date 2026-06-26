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
