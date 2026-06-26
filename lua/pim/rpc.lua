local M = {}

local jsonl = require("pim.jsonl")

local state = {
  job_id = nil,
  next_id = 1,
  stdout_pending = "",
  opts = {},
  on_event = nil,
}

local function notify(message, level)
  vim.schedule(function()
    vim.notify(message, level or vim.log.levels.INFO, { title = "pim" })
  end)
end

local function emit(event)
  if state.on_event then
    vim.schedule(function()
      state.on_event(event)
    end)
  end
end

local function consume_stdout(chunk)
  jsonl.consume_chunk(
    function() return state.stdout_pending end,
    function(p) state.stdout_pending = p end,
    chunk,
    function(event) emit(event) end
  )
end

function M.setup(opts)
  state.opts = opts or {}
  state.on_event = state.opts.on_event
end

function M.is_running()
  return state.job_id ~= nil
end

function M.start(extra_args)
  if state.job_id then
    return state.job_id
  end

  local cmd = vim.deepcopy(state.opts.pi_cmd or { "pi", "--mode", "rpc" })
  if extra_args and #extra_args > 0 then
    vim.list_extend(cmd, extra_args)
  end
  state.stdout_pending = ""
  -- Identity for this specific process so a late on_exit (e.g. from a process
  -- replaced by reload) cannot clear a newer job handle.
  local handle = {}
  state.job_id = vim.fn.jobstart(cmd, {
    stdin = "pipe",
    env = state.opts.env,
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data)
      if not data or #data == 0 then
        return
      end
      consume_stdout(table.concat(data, "\n"))
    end,
    on_stderr = function(_, data)
      if not data or #data == 0 then
        return
      end
      local text = table.concat(data, "\n")
      if text:gsub("%s", "") ~= "" then
        emit({ type = "pim_stderr", text = text })
      end
    end,
    on_exit = function(_, code, signal)
      if state.job_id == handle.id then
        state.job_id = nil
      end
      emit({ type = "pim_exit", job_id = handle.id, code = code, signal = signal })
    end,
  })
  handle.id = state.job_id

  if state.job_id <= 0 then
    local failed = state.job_id
    state.job_id = nil
    error("failed to start pi RPC process: jobstart returned " .. tostring(failed))
  end

  notify("started pi RPC process")
  return state.job_id
end

function M.stop()
  if not state.job_id then
    return
  end
  vim.fn.jobstop(state.job_id)
  state.job_id = nil
end

function M.send(command)
  M.start()
  command.id = command.id or ("pim-" .. state.next_id)
  state.next_id = state.next_id + 1
  vim.fn.chansend(state.job_id, vim.json.encode(command) .. "\n")
  return command.id
end

function M.prompt(message, streaming_behavior)
  return M.send({
    type = "prompt",
    message = message,
    streamingBehavior = streaming_behavior,
  })
end

function M.steer(message)
  return M.send({
    type = "steer",
    message = message,
  })
end

function M.follow_up(message)
  return M.send({
    type = "follow_up",
    message = message,
  })
end

function M.get_state()
  return M.send({ type = "get_state" })
end

function M.new_session(parent_session)
  local command = { type = "new_session" }
  if parent_session then
    command.parentSession = parent_session
  end
  return M.send(command)
end

function M.set_session_name(name)
  return M.send({ type = "set_session_name", name = name })
end

function M.abort()
  return M.send({ type = "abort" })
end

return M
