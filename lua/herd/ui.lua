local M = {}
local View = require("herd.view")
local MAX_TEXT = 2 * 1024 * 1024
local MAX_LINES = 20000
local TRUNCATED = "[Herd transcript truncated; Pi's persistent session retains its own history.]\n"
local queue = {}
local active

--- Removes terminal escape sequences and control bytes from display-only text.
function M.clean(text)
  local cleaned = tostring(text or "")
    :gsub("\27%][^\7]*\7", "")
    :gsub("\27%][^\27]*\27\\", "")
    :gsub("\27%[[0-?]*[ -/]*[@-~]", "")
    :gsub("\27.", "")
    :gsub("[%z\1-\8\11-\31\127]", "")
  return cleaned
end

--- Returns text blocks and readable metadata without embedding binary image data.
local function content_text(content)
  if type(content) == "string" then
    return content
  end
  local text = {}
  for _, block in ipairs(type(content) == "table" and content or {}) do
    if block.type == "text" then
      text[#text + 1] = block.text or ""
    elseif block.type ~= "thinking" then
      text[#text + 1] = "[" .. tostring(block.type) .. " content]"
    end
  end
  return table.concat(text, "\n")
end

--- Encodes complete tool arguments or result metadata for the transcript.
local function json(value)
  local ok, text = pcall(vim.json.encode, value)
  return ok and text or "[Could not encode tool data]"
end

--- Returns whether this session is visible in the current tabpage.
function M.visible(session)
  for _, win in ipairs(session.buf and vim.fn.win_findbuf(session.buf) or {}) do
    if vim.api.nvim_win_get_tabpage(win) == vim.api.nvim_get_current_tabpage() then
      return true
    end
  end
  return false
end

--- Keeps transcript storage bounded, including a single oversized result.
local function trim(session)
  local size = 0
  for _, entry in ipairs(session.entries) do
    size = size + #entry.text
  end
  while size > MAX_TEXT and #session.entries > 1 do
    local removed = table.remove(session.entries, 1)
    for id, entry in pairs(session.tools or {}) do
      if entry == removed then
        session.tools[id] = nil
      end
    end
    size = size - #removed.text
    session.truncated = true
  end
  if size > MAX_TEXT then
    session.entries[1].text = session.entries[1].text:sub(-MAX_TEXT)
    session.truncated = true
  end
end

--- Renders above the editable prompt without replacing its draft or moving a reader's cursor.
function M.render(session)
  if not session.buf or not vim.api.nvim_buf_is_valid(session.buf) then
    return
  end
  trim(session)
  local texts = session.truncated and { TRUNCATED } or {}
  for _, entry in ipairs(session.entries) do
    texts[#texts + 1] = M.clean(entry.text)
  end
  local lines = vim.split(table.concat(texts, ""), "\n", { plain = true })
  if #lines > MAX_LINES then
    lines = vim.list_slice(lines, #lines - MAX_LINES + 2)
    table.insert(lines, 1, (TRUNCATED:gsub("\n$", "")))
  end
  local count = vim.api.nvim_buf_line_count(session.buf)
  local cursors = {}
  for _, win in ipairs(vim.fn.win_findbuf(session.buf)) do
    local pos = vim.api.nvim_win_get_cursor(win)
    cursors[win] = { pos = pos, follow = pos[1] >= count - 1 }
  end
  vim.api.nvim_buf_set_lines(session.buf, 0, count - 1, false, lines)
  for win, cursor in pairs(cursors) do
    if vim.api.nvim_win_is_valid(win) then
      local last = vim.api.nvim_buf_line_count(session.buf)
      local row = cursor.follow and last or math.min(cursor.pos[1], last)
      local column = cursor.follow and cursor.pos[1] ~= count and 0 or cursor.pos[2]
      pcall(vim.api.nvim_win_set_cursor, win, { row, column })
    end
  end
end

--- Coalesces high-frequency streaming updates into bounded editor redraws.
local function redraw(session)
  trim(session)
  if session.render_pending then
    return
  end
  session.render_pending = true
  vim.defer_fn(function()
    session.render_pending = false
    if M.visible(session) then
      M.render(session)
    end
  end, 50)
end

--- Appends a transcript entry and returns its handle for later authoritative replacement.
function M.append(session, text)
  local entry = { text = text }
  session.entries[#session.entries + 1] = entry
  redraw(session)
  return entry
end

--- Creates the hidden prompt buffer and its local editing controls.
function M.create(session, submit, hide, on_delete)
  session.entries = {}
  session.tools = {}
  session.statuses = {}
  session.buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(session.buf, ("herd://pi/%d"):format(session.id))
  vim.bo[session.buf].buftype = "prompt"
  vim.bo[session.buf].bufhidden = "hide"
  vim.bo[session.buf].swapfile = false
  vim.bo[session.buf].filetype = "herd"
  vim.fn.prompt_setprompt(session.buf, "You> ")
  vim.fn.prompt_setcallback(session.buf, function(text)
    submit(session, text)
  end)
  vim.keymap.set("n", "q", hide, { buffer = session.buf, desc = "Hide Herd" })
  vim.keymap.set("n", "i", function()
    vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(session.buf), 0 })
    vim.cmd.startinsert({ bang = true })
  end, { buffer = session.buf, desc = "Edit Herd prompt" })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = session.buf,
    once = true,
    callback = function()
      M.cancel_dialogs(session)
      session:stop()
      if on_delete then
        on_delete(session)
      end
    end,
  })
  M.append(
    session,
    ("Pi #%d — %s\nEnter: prompt/follow-up | Normal mode q: hide | :HerdAbort / :HerdSteer\n\n"):format(
      session.id,
      session.root
    )
  )
end

--- Displays a session in this tab's reusable floating or docked Herd view.
function M.show(session)
  M.render(session)
  View.show(session.buf)
  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(session.buf), 0 })
  vim.cmd.startinsert({ bang = true })
end

--- Hides this tab's Herd view, retaining its buffers and subprocesses.
function M.hide()
  View.hide()
end

--- Replaces only the editable prompt line with extension-provided text.
local function prefill(session, text)
  if not vim.api.nvim_buf_is_valid(session.buf) then
    return
  end
  -- Prompt buffers submit one line; multiline content uses the editor dialog instead.
  text = M.clean(text):gsub("\n", " ")
  local last = vim.api.nvim_buf_line_count(session.buf)
  vim.api.nvim_buf_set_lines(session.buf, last - 1, last, false, { "You> " .. text })
end

--- Shows a cancellable multiline editor and returns its cleanup function.
local function editor(request, finish)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(request.prefill or "", "\n", { plain = true }))
  local width = math.max(1, math.min(90, vim.o.columns - 4))
  local height = math.max(1, math.min(18, vim.o.lines - 6))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    border = "rounded",
    zindex = 60, -- Above the Herd popup, below native completion and command-line surfaces.
    title = " " .. M.clean(request.title or "Pi input") .. " (Ctrl-S: send, q: cancel) ",
  })
  local closed = false
  local function close()
    if closed then
      return
    end
    closed = true
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  vim.keymap.set({ "n", "i" }, "<C-s>", function()
    local value = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    finish({ value = value })
  end, { buffer = buf })
  vim.keymap.set("n", "q", function()
    finish({ cancelled = true })
  end, { buffer = buf })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      if not closed then
        finish({ cancelled = true })
      end
    end,
  })
  return close
end

local next_dialog

--- Releases the active dialog before displaying the next session's request.
local function finish_dialog(item, response)
  if item.done then
    return
  end
  item.done = true
  if item.timer and not item.timer:is_closing() then
    item.timer:stop()
    item.timer:close()
  end
  if item.cleanup then
    item.cleanup()
  end
  item.session:respond(item.request.id, response)
  if active == item then
    active = nil
  end
  vim.schedule(next_dialog)
end

--- Serializes dialogs so concurrent agents cannot overwrite each other's prompts.
next_dialog = function()
  if active then
    return
  end
  local item = table.remove(queue, 1)
  if not item then
    return
  end
  if item.session.closed or item.session.stopping or item.done then
    vim.schedule(next_dialog)
    return
  end
  active = item
  local request = item.request
  local title = ("Pi #%d: %s"):format(item.session.id, M.clean(request.title or request.method))
  local function finish(response)
    finish_dialog(item, response)
  end
  if request.method == "select" then
    vim.ui.select(request.options or {}, { prompt = title }, function(value)
      finish(value ~= nil and { value = value } or { cancelled = true })
    end)
  elseif request.method == "confirm" then
    vim.ui.select({ "No", "Yes" }, { prompt = title .. " " .. M.clean(request.message) }, function(value)
      finish(value ~= nil and { confirmed = value == "Yes" } or { cancelled = true })
    end)
  elseif request.method == "input" then
    vim.ui.input({ prompt = title .. ": ", default = "" }, function(value)
      finish(value ~= nil and { value = value } or { cancelled = true })
    end)
  elseif request.method == "editor" then
    item.cleanup = editor(request, finish)
  end
end

--- Cancels pending UI work for a stopped or deleted session.
function M.cancel_dialogs(session)
  if active and active.session == session then
    finish_dialog(active, { cancelled = true })
  end
  for _, item in ipairs(queue) do
    if item.session == session then
      finish_dialog(item, { cancelled = true })
    end
  end
end

--- Adapts Pi's supported extension UI methods to native Neovim surfaces.
function M.extension(session, request)
  if session.dialogs[request.id] then
    local item = { session = session, request = request }
    queue[#queue + 1] = item
    if not M.visible(session) then
      vim.notify(("Pi #%d needs input: %s"):format(session.id, M.clean(request.title)), vim.log.levels.WARN)
    end
    if type(request.timeout) == "number" and request.timeout >= 0 then
      item.timer = vim.defer_fn(function()
        finish_dialog(item, { cancelled = true })
      end, math.min(request.timeout, 2147483647))
    end
    next_dialog()
  elseif request.method == "notify" then
    local levels = { info = vim.log.levels.INFO, warning = vim.log.levels.WARN, error = vim.log.levels.ERROR }
    vim.notify(
      M.clean(request.message),
      levels[request.notifyType] or vim.log.levels.INFO,
      { title = "Pi #" .. session.id }
    )
  elseif request.method == "setTitle" then
    session.title = M.clean(request.title)
  elseif request.method == "setStatus" and type(request.statusKey) == "string" then
    session.statuses[request.statusKey] = request.statusText and M.clean(request.statusText) or nil
  elseif request.method == "setWidget" and type(request.widgetLines) == "table" then
    M.append(session, "\n[" .. M.clean(request.widgetKey) .. "]\n" .. table.concat(request.widgetLines, "\n") .. "\n")
  elseif request.method == "set_editor_text" then
    prefill(session, request.text)
  end
end

--- Reconciles streamed assistant text with the final authoritative message.
local function assistant(session, event)
  if event.type == "message_start" then
    session.assistant = M.append(session, "\nPi> ")
    session.blocks = {}
  elseif session.assistant then
    if event.type == "message_update" then
      local update = event.assistantMessageEvent or {}
      local index = update.contentIndex or 0
      if update.type == "text_delta" then
        session.blocks[index] = ((session.blocks[index] or "") .. (update.delta or "")):sub(-MAX_TEXT)
      elseif update.type == "text_end" then
        session.blocks[index] = (update.content or session.blocks[index] or ""):sub(-MAX_TEXT)
      end
      local parts = {}
      for _, key in ipairs(vim.tbl_keys(session.blocks)) do
        parts[#parts + 1] = key
      end
      table.sort(parts)
      local size = 0
      for _, key in ipairs(parts) do
        size = size + #session.blocks[key]
      end
      while size > MAX_TEXT and #parts > 1 do
        local key = table.remove(parts, 1)
        size = size - #session.blocks[key]
        session.blocks[key] = nil
        session.truncated = true
      end
      local texts = {}
      for _, key in ipairs(parts) do
        texts[#texts + 1] = session.blocks[key]
      end
      session.assistant.text = "\nPi> " .. table.concat(texts, "\n")
    elseif event.type == "message_end" then
      local message = event.message
      session.assistant.text = "\nPi> " .. content_text(message.content) .. "\n"
      if message.errorMessage then
        session.assistant.text = session.assistant.text .. "Error: " .. message.errorMessage .. "\n"
      end
      session.assistant = nil
      session.blocks = nil
    end
    redraw(session)
  end
end

--- Renders transcript events without exposing model thinking or treating output as commands.
function M.event(session, event)
  local kind = event.type
  if kind == "extension_ui_request" then
    M.extension(session, event)
  elseif
    kind == "message_update"
    or (kind == "message_start" or kind == "message_end") and (event.message or {}).role == "assistant"
  then
    assistant(session, event)
  elseif kind == "tool_execution_start" then
    session.tools[event.toolCallId] =
      M.append(session, "\nTool: " .. event.toolName .. "\nArguments: " .. json(event.args) .. "\n[running]\n")
  elseif kind == "tool_execution_end" then
    local entry = session.tools[event.toolCallId]
    local result = event.result or {}
    local text = content_text(result.content)
    if result.details ~= nil then
      text = text .. "\nDetails: " .. json(result.details)
    end
    if entry then
      entry.text = entry.text:gsub("%[running%]\n$", "")
        .. text
        .. ("\n[%s, %s ms]\n"):format(event.isError and "error" or "done", tostring(event.durationMs or "?"))
      session.tools[event.toolCallId] = nil
      redraw(session)
    else
      M.append(session, "\nTool result: " .. text .. "\n")
    end
  elseif kind == "herd_error" or kind == "extension_error" then
    M.append(session, "\nError: " .. tostring(event.error) .. "\n")
  elseif kind == "herd_stderr" then
    M.append(session, "\n[Pi stderr] " .. event.text .. "\n")
  elseif kind == "herd_exit" then
    M.cancel_dialogs(session)
    session.tools = {}
    session.blocks = nil
    session.assistant = nil
    M.append(session, ("\n[Pi process exited: %d]\n"):format(event.code))
  elseif kind == "queue_update" then
    M.append(session, "\n[Queue] " .. json({ steering = event.steering, followUp = event.followUp }) .. "\n")
  elseif kind:find("retry", 1, true) or kind:find("compaction", 1, true) then
    M.append(session, "\n[" .. kind .. "] " .. json(event) .. "\n")
  end
end

return M
