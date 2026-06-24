local M = {}

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

local function handle_line(line)
  if line == "" then
    return
  end
  local ok, decoded = pcall(vim.json.decode, line)
  if not ok then
    emit({ type = "pim_parse_error", line = line, error = decoded })
    return
  end
  emit(decoded)
end

local function consume_stdout(chunk)
  state.stdout_pending = state.stdout_pending .. chunk
  while true do
    local newline = state.stdout_pending:find("\n", 1, true)
    if not newline then
      break
    end
    local line = state.stdout_pending:sub(1, newline - 1)
    state.stdout_pending = state.stdout_pending:sub(newline + 1)
    if line:sub(-1) == "\r" then
      line = line:sub(1, -2)
    end
    handle_line(line)
  end
end

function M.setup(opts)
  state.opts = opts or {}
  state.on_event = state.opts.on_event
end

function M.is_running()
  return state.job_id ~= nil
end

function M.start()
  if state.job_id then
    return state.job_id
  end

  local cmd = state.opts.pi_cmd or { "pi", "--mode", "rpc" }
  state.stdout_pending = ""
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
      local old = state.job_id
      state.job_id = nil
      emit({ type = "pim_exit", job_id = old, code = code, signal = signal })
    end,
  })

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

function M.abort()
  return M.send({ type = "abort" })
end

return M
