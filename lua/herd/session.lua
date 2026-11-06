local Session = {}
Session.__index = Session

local MAX_RECORD_BYTES = 16 * 1024 * 1024
local REQUEST_TIMEOUT_MS = 60000

--- Creates an isolated Pi RPC transport. No shell command interpolation is used.
function Session.new(opts)
  return setmetatable({
    id = opts.id,
    root = opts.root,
    command = opts.command or { "pi", "--mode", "rpc" },
    on_event = opts.on_event or function() end,
    state = "starting",
    running = false,
    ready = false,
    closed = false,
    stopping = false,
    pending = {},
    dialogs = {},
    sequence = 0,
    runs = 0,
    stdout = "",
  }, Session)
end

--- Sends a local event to the editor-side session manager.
function Session:emit(event)
  self.on_event(self, event)
end

--- Updates the visible state without hiding outstanding human-input requests.
function Session:set_state(state)
  self.base_state = state
  self.state = next(self.dialogs) and "waiting" or state
  self:emit({ type = "herd_state" })
end

--- Writes exactly one JSONL record to the subprocess stdin.
function Session:write(record)
  if self.closed or self.stopping or not self.job then
    return false, "Pi is not running"
  end
  local ok, result = pcall(vim.fn.chansend, self.job, vim.json.encode(record) .. "\n")
  if not ok or result == 0 then
    return false, "Could not write to Pi stdin"
  end
  return true
end

--- Correlates an RPC command with a bounded response deadline.
function Session:request(command, fields, callback)
  self.sequence = self.sequence + 1
  local id = ("herd-%d-%d"):format(self.id, self.sequence)
  local record = vim.tbl_extend("force", fields or {}, { id = id, type = command })
  self.pending[id] = { callback = callback, command = command }
  local ok, err = self:write(record)
  if not ok then
    self.pending[id] = nil
    return false, err
  end
  local expire
  expire = function()
    if self.closed or not self.pending[id] then
      return
    end
    -- Human input can take much longer than a normal protocol response.
    if next(self.dialogs) then
      self.pending[id].timer = vim.defer_fn(expire, REQUEST_TIMEOUT_MS)
      return
    end
    self.pending[id] = nil
    self:set_state("error")
    self:emit({ type = "herd_error", error = command .. " response timed out" })
    if command == "get_state" and not self.ready then
      self:stop()
    end
  end
  self.pending[id].timer = vim.defer_fn(expire, REQUEST_TIMEOUT_MS)
  return true
end

--- Processes one complete, decoded RPC event.
function Session:receive(event)
  if event.type == "response" then
    local pending = event.id and self.pending[event.id]
    if pending then
      pending.timer:stop()
      pending.timer:close()
      self.pending[event.id] = nil
    end
    if event.success == false then
      if pending and pending.command == "prompt" and not pending.was_running then
        self.running = false
      end
      self:set_state("error")
      self:emit({ type = "herd_error", error = event.error or "RPC command failed" })
    elseif pending and pending.callback then
      pending.callback(event.data or {})
    end
  elseif event.type == "agent_start" then
    self.runs = self.runs + 1
    self.running = true
    self.failed = false
    self:set_state("running")
  elseif event.type == "agent_settled" then
    self.running = false
    self:set_state(self.failed and "error" or "idle")
  elseif event.type == "message_end" and type(event.message) == "table" then
    if event.message.stopReason == "error" then
      self.failed = true
      self:set_state("error")
    end
  elseif event.type == "extension_ui_request" then
    if vim.tbl_contains({ "select", "confirm", "input", "editor" }, event.method) then
      if type(event.id) ~= "string" or self.dialogs[event.id] then
        return
      end
      self.dialogs[event.id] = event
      self:set_state(self.base_state or "idle")
    end
  end
  self:emit(event)
end

--- Joins job callback fragments and splits protocol records only on LF.
function Session:feed(data)
  if self.closed or not data then
    return
  end
  local chunk = table.concat(data, "\n")
  self.stdout = self.stdout .. chunk
  while true do
    local newline = self.stdout:find("\n", 1, true)
    if not newline then
      break
    end
    local line = self.stdout:sub(1, newline - 1):gsub("\r$", "")
    self.stdout = self.stdout:sub(newline + 1)
    if #line > MAX_RECORD_BYTES then
      self:emit({ type = "herd_error", error = "RPC record exceeded the 16 MiB limit" })
      self:stop()
      return
    end
    if line ~= "" then
      local ok, event = pcall(vim.json.decode, line)
      if ok and type(event) == "table" and type(event.type) == "string" then
        local handled, err = pcall(self.receive, self, event)
        if not handled then
          self:set_state("error")
          self:emit({ type = "herd_error", error = "Invalid RPC event: " .. tostring(err) })
        end
      else
        self:set_state("error")
        self:emit({ type = "herd_error", error = "Invalid JSONL record from Pi" })
      end
    end
  end
  if #self.stdout > MAX_RECORD_BYTES then
    self:emit({ type = "herd_error", error = "Unterminated RPC record exceeded the 16 MiB limit" })
    self.stdout = ""
    self:stop()
  end
end

--- Starts Pi and verifies readiness using a real get_state response.
function Session:start()
  local ok, job = pcall(vim.fn.jobstart, self.command, {
    cwd = self.root,
    on_stdout = function(_, data)
      self:feed(data)
    end,
    on_stderr = function(_, data)
      local text = table.concat(data or {}, "\n")
      if text ~= "" then
        self:emit({ type = "herd_stderr", text = text })
      end
    end,
    on_exit = function(_, code)
      if self.stdout ~= "" then
        self:emit({ type = "herd_error", error = "Pi exited with an incomplete JSONL record" })
      end
      self.closed = true
      self.ready = false
      self.running = false
      self:clear_pending()
      self.dialogs = {}
      self:set_state(self.stopping and "stopped" or "error")
      self:emit({ type = "herd_exit", code = code, expected = self.stopping })
    end,
  })
  self.job = ok and job or -1
  if self.job <= 0 then
    self.closed = true
    self:set_state("error")
    self:emit({ type = "herd_error", error = "Could not start Pi; check the configured executable" })
    return false
  end
  self:request("get_state", {}, function(state)
    self.ready = true
    self.pi_session_id = state.sessionId
    self.session_file = state.sessionFile
    self.running = state.isStreaming == true
    self:set_state(self.running and "running" or "idle")
  end)
  return true
end

--- Sends a prompt; busy sessions queue ordinary submissions as follow-ups.
function Session:prompt(message, behavior)
  if not self.ready or self.closed or self.stopping then
    return false, "Pi is not ready"
  end
  local was_running = self.running
  local runs = self.runs
  local fields = { message = message }
  if was_running then
    fields.streamingBehavior = behavior or "followUp"
  end
  local ok, err = self:request("prompt", fields, function(data)
    if data.disposition == "handled" and not was_running and self.runs == runs then
      self.running = false
      self:set_state("idle")
    end
  end)
  if ok then
    self.pending[("herd-%d-%d"):format(self.id, self.sequence)].was_running = was_running
  end
  if ok and not was_running then
    -- Block duplicate idle submissions before agent_start arrives.
    self.running = true
    self.failed = false
    self:set_state("running")
  end
  return ok, err
end

--- Drops queued prompts before aborting so abort cannot start follow-up work.
function Session:abort()
  return self:request("clear_queue", {}, function()
    self:request("abort", {}, function()
      self.running = false
      self:set_state("idle")
    end)
  end)
end

--- Resolves a supported extension dialog exactly once.
function Session:respond(id, response)
  if not self.dialogs[id] then
    return false
  end
  self.dialogs[id] = nil
  local ok = self:write(vim.tbl_extend("force", response, { type = "extension_ui_response", id = id }))
  self:set_state(self.base_state or "idle")
  return ok
end

--- Releases request deadline timers when the process stops or exits.
function Session:clear_pending()
  for _, pending in pairs(self.pending) do
    pending.timer:stop()
    pending.timer:close()
  end
  self.pending = {}
end

--- Requests orderly shutdown and terminates an unresponsive process after a grace period.
function Session:stop()
  if self.closed or self.stopping then
    return
  end
  for id in pairs(self.dialogs) do
    self:respond(id, { cancelled = true })
  end
  self.stopping = true
  self:clear_pending()
  self:set_state("stopped")
  if self.job and self.job > 0 then
    pcall(vim.fn.chanclose, self.job, "stdin")
    vim.defer_fn(function()
      if not self.closed then
        pcall(vim.fn.jobstop, self.job)
      end
    end, 1500)
  end
end

return Session
