-- Deterministic Pi RPC fixture. Invoked as a clean Neovim Lua subprocess by run.lua.
local input = vim.uv.new_pipe(false)
input:open(0)
local buffer = ""
local log = assert(vim.env.HERD_TEST_LOG)

--- Emits a complete JSONL protocol record without a terminal interface.
local function emit(record)
  io.stdout:write(vim.json.encode(record), "\n")
  io.stdout:flush()
end

--- Records requests and implements the RPC subset needed by the workspace tests.
local function handle(request)
  vim.fn.writefile({ vim.json.encode(request) }, log, "a")
  if request.type == "get_state" then
    emit({
      type = "response",
      id = request.id,
      success = true,
      data = { sessionId = "fake-" .. vim.uv.os_getpid(), isStreaming = false },
    })
  elseif request.type == "prompt" then
    emit({ type = "response", id = request.id, success = true, data = { disposition = "started" } })
    emit({ type = "agent_start" })
    emit({ type = "message_start", message = { role = "assistant", content = {} } })
    emit({
      type = "message_update",
      assistantMessageEvent = { type = "text_delta", contentIndex = 0, delta = "streaming" },
    })
    emit({
      type = "message_end",
      message = { role = "assistant", content = { { type = "text", text = "Final response: " .. request.message } } },
    })
    if request.message ~= "hold" then
      emit({ type = "agent_settled", aborted = false })
    end
  elseif request.type == "clear_queue" or request.type == "abort" then
    emit({ type = "response", id = request.id, success = true, data = {} })
    if request.type == "abort" then
      emit({ type = "agent_settled", aborted = true })
    end
  end
end

input:read_start(function(err, chunk)
  assert(not err, err)
  if not chunk then
    input:close()
    return
  end
  buffer = buffer .. chunk
  while true do
    local newline = buffer:find("\n", 1, true)
    if not newline then
      break
    end
    local line = buffer:sub(1, newline - 1)
    buffer = buffer:sub(newline + 1)
    if line ~= "" then
      local request = vim.json.decode(line)
      vim.schedule(function()
        handle(request)
      end)
    end
  end
end)

while not input:is_closing() do
  vim.wait(10)
end
