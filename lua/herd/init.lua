-- Pi Herd prototype. Requires an installed Pi CLI with the documented JSONL RPC protocol.
-- :HerdNew [root] creates a persistent Pi session using the user's normal Pi configuration.
-- Enter sends a prompt/follow-up; Normal mode q hides its view without stopping Pi.
-- Sessions are listed buffers: use normal buffer/window/tab navigation. Wiping a buffer stops its Pi.
-- Neovim exit stops all owned processes; conversation files remain in Pi's session storage.
-- Keys: <leader>h list, hn new, ht toggle, h]/h[ cycle, hs selected lines, hk stop, ha abort, hr steer.
-- Normal commands: HerdNew, HerdList, HerdToggle, HerdStop, HerdAbort, HerdSteer [text].
-- Herd opens in a floating popup; HerdLayout / <leader>hf toggles docking without restarting Pi.
-- HerdFloat and HerdDock select a presentation explicitly; setup({ view = "split" }) changes the default.
-- Transcript: full textual final tool results, up to 2 MiB/20,000 lines; images are represented by labels.
-- Pi tools can independently truncate results; the frontend does not fetch external output files.
-- Optional setup({ command = { "pi", "--mode", "rpc", ... } }) overrides launch arguments.
-- This is an RPC frontend, not the Pi TUI: TUI-only commands and custom extension UIs are unsupported.
local M = { sessions = {}, current = nil }
local Session = require("herd.session")
local UI = require("herd.ui")
local View = require("herd.view")
local symbols = { starting = "…", idle = "○", running = "◐", waiting = "?", error = "!", stopped = "×" }
local configured = false
local options = {}
local sequence = 0

--- Returns the session associated with the current buffer or last selected agent.
function M.active()
  for _, session in ipairs(M.sessions) do
    if session.buf == vim.api.nvim_get_current_buf() then
      M.current = session
      return session
    end
  end
  local selected = View.buffer()
  for _, session in ipairs(M.sessions) do
    if session.buf == selected then
      M.current = session
      return session
    end
  end
  return M.current
end

--- Redraws the statusline without requiring Lualine to be loaded.
local function refresh()
  View.refresh()
  local lualine = package.loaded.lualine
  if lualine and type(lualine.refresh) == "function" then
    lualine.refresh({ place = { "statusline" } })
  else
    vim.cmd.redrawstatus()
  end
end

--- Receives transport events and updates transcript, unread state, and notifications.
local function on_event(session, event)
  UI.event(session, event)
  local hidden = not UI.visible(session)
  if event.type == "agent_start" then
    session.unread = false
  elseif event.type == "agent_settled" and hidden then
    session.unread = true
    vim.notify(
      ("Pi #%d %s"):format(session.id, event.aborted and "aborted" or session.failed and "failed" or "finished"),
      session.failed and vim.log.levels.ERROR or vim.log.levels.INFO,
      {
        title = "Herd",
      }
    )
  elseif (event.type == "herd_error" or event.type == "herd_exit" and not event.expected) and hidden then
    vim.notify(
      ("Pi #%d: %s"):format(session.id, UI.clean(event.error or "process exited")),
      vim.log.levels.ERROR,
      { title = "Herd" }
    )
  end
  if event.type == "herd_state" or event.type == "agent_settled" or event.type == "agent_start" then
    refresh()
  end
end

--- Returns a project-root default without changing Neovim's current directory.
function M.default_root()
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  local start = name ~= "" and not name:find("://", 1, true) and vim.fs.dirname(name) or vim.fn.getcwd()
  local git = vim.fs.root(start, ".git")
  if git then
    return git
  end
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    if type(client.config.root_dir) == "string" then
      return client.config.root_dir
    end
  end
  return vim.fn.getcwd()
end

--- Displays an agent in this tab's Herd view and clears its hidden-completion indicator.
function M.show(session)
  if not session or not vim.api.nvim_buf_is_valid(session.buf) then
    return
  end
  M.current = session
  session.unread = false
  UI.show(session)
  refresh()
end

--- Sends text only after validating that the selected Pi instance is ready.
function M.send(session, text, behavior)
  session = session or M.active()
  if not session then
    vim.notify("Create a Pi session with :HerdNew first", vim.log.levels.WARN)
    return false
  end
  if type(text) ~= "string" or not text:find("%S") then
    return false
  end
  local ok, err = session:prompt(text, behavior)
  if not ok then
    UI.append(session, "\n[Not sent] " .. err .. "\nDraft: " .. text .. "\n")
    vim.notify(err, vim.log.levels.WARN, { title = "Herd" })
    return false
  end
  UI.append(session, "\nYou> " .. text .. "\n")
  return true
end

--- Starts one explicitly rooted Pi instance or prompts for its directory.
function M.new(root)
  if not root or root == "" then
    vim.ui.input({ prompt = "Pi working directory: ", default = M.default_root(), completion = "dir" }, function(value)
      if value and value ~= "" then
        M.new(value)
      end
    end)
    return
  end
  root = vim.fs.normalize(vim.fn.fnamemodify(vim.fs.normalize(root), ":p"))
  if vim.fn.isdirectory(root) ~= 1 then
    vim.notify("Pi root is not a directory: " .. root, vim.log.levels.ERROR)
    return
  end
  sequence = sequence + 1
  local session = Session.new({ id = sequence, root = root, command = options.command, on_event = on_event })
  M.sessions[#M.sessions + 1] = session
  M.current = session
  UI.create(session, M.send, function()
    UI.hide(session)
  end, function(deleted)
    for i, existing in ipairs(M.sessions) do
      if existing == deleted then
        table.remove(M.sessions, i)
        break
      end
    end
    if M.current == deleted then
      M.current = M.sessions[#M.sessions]
    end
    refresh()
  end)
  M.show(session)
  session:start()
  return session
end

--- Opens the session picker, offering creation when there are no agents.
function M.list()
  if #M.sessions == 0 then
    return M.new()
  end
  vim.ui.select(M.sessions, {
    prompt = "Herd sessions",
    format_item = function(session)
      return ("%s π %s — %s"):format(M.symbol(session), M.label(session), session.root)
    end,
  }, function(session)
    if session then
      M.show(session)
    end
  end)
end

--- Shows or hides the selected session without changing process lifetime.
function M.toggle()
  local session = M.active()
  if not session then
    return M.new()
  end
  if UI.visible(session) then
    UI.hide(session)
  else
    M.show(session)
  end
end

--- Cycles between sessions using their creation order.
function M.cycle(direction)
  if #M.sessions == 0 then
    return M.new()
  end
  local current = M.active()
  local index = 1
  for i, session in ipairs(M.sessions) do
    if session == current then
      index = i
      break
    end
  end
  M.show(M.sessions[(index - 1 + direction) % #M.sessions + 1])
end

--- Stops the chosen Pi instance but retains its readable transcript.
function M.stop()
  local session = M.active()
  if session then
    UI.cancel_dialogs(session)
    session:stop()
  end
end

--- Cancels queued work and aborts the active run without killing Pi.
function M.abort()
  local session = M.active()
  if session and session.ready then
    session:abort()
  end
end

--- Prompts for steering text or sends the supplied text to the selected agent.
function M.steer(text)
  local session = M.active()
  if not session then
    return
  end
  if text and text ~= "" then
    return M.send(session, text, "steer")
  end
  vim.ui.input({ prompt = "Steer Pi: " }, function(value)
    if value then
      M.send(session, value, "steer")
    end
  end)
end

--- Sends selected lines with their explicit source path, without implicitly writing the file.
function M.selection()
  local session = M.active()
  local buf = vim.api.nvim_get_current_buf()
  local first, last = vim.fn.line("v"), vim.fn.line(".")
  if first > last then
    first, last = last, first
  end
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, first - 1, last, false), "\n")
  local path = vim.api.nvim_buf_get_name(buf)
  vim.cmd("normal! \27")
  M.send(session, ("Selected lines %d-%d from %s (possibly unsaved):\n%s"):format(first, last, path, text))
end

--- Changes the selected session's window presentation without changing process ownership.
function M.layout(mode)
  local session = M.active()
  if not session then
    vim.notify("Create a Pi session with :HerdNew first", vim.log.levels.WARN)
    return
  end
  UI.render(session)
  View.layout(mode, session.buf)
  M.current = session
  session.unread = false
  refresh()
end

--- Returns a safe display name without interpreting statusline syntax from user/model text.
function M.label(session)
  local name = type(session.name) == "string" and UI.clean(session.name):gsub("[\r\n\t]", " ") or ""
  return name ~= "" and name or ("Session %d"):format(session.id)
end

--- Renames a connected Pi session and waits for acknowledgement before updating its tab.
function M.rename(name, session)
  session = session or M.active()
  if not session or not session.ready or session.closed or session.stopping then
    vim.notify("Pi must be ready to rename its session", vim.log.levels.WARN)
    return
  end
  if name == nil then
    vim.ui.input({ prompt = "Session name: ", default = M.label(session) }, function(value)
      if value ~= nil then
        M.rename(value, session)
      end
    end)
    return
  end
  name = UI.clean(name):gsub("[\r\n\t]", " "):match("^%s*(.-)%s*$")
  if name == "" or vim.fn.strchars(name) > 80 then
    vim.notify("Choose a session name between 1 and 80 characters", vim.log.levels.WARN)
    return
  end
  local ok, err = session:request("set_session_name", { name = name }, function()
    session.name = name
    refresh()
  end)
  if not ok then
    vim.notify(err, vim.log.levels.ERROR)
  end
end

--- Confirms destructive tab closure; stopping a session alone still retains its transcript.
function M.close(session)
  session = session or M.active()
  if not session or session.close_pending then
    return
  end
  session.close_pending = true
  vim.ui.select({ "Cancel", "Close session" }, {
    prompt = "Close " .. M.label(session) .. "? Stops Pi and discards its unsent draft.",
  }, function(choice)
    session.close_pending = nil
    if choice ~= "Close session" then
      return
    end
    local replacement
    for i, existing in ipairs(M.sessions) do
      if existing == session then
        replacement = M.sessions[i + 1] or M.sessions[i - 1]
        break
      end
    end
    if not vim.api.nvim_buf_is_valid(session.buf) then
      return
    end
    if replacement then
      UI.render(replacement)
    end
    View.remove(session.buf, replacement and replacement.buf)
    UI.cancel_dialogs(session)
    session:stop()
    vim.api.nvim_buf_delete(session.buf, { force = true })
    refresh()
  end)
end

--- Routes a winbar click through a fixed Lua callback, never through generated commands.
function M.tab_click(id, clicks, button)
  if button ~= "l" then
    return
  end
  local win = vim.fn.getmousepos().winid
  vim.schedule(function()
    if win > 0 and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_current_win(win)
    end
    if id == 0 then
      if clicks == 1 then
        M.new()
      end
      return
    end
    for _, session in ipairs(M.sessions) do
      if session.id == id then
        M.show(session)
        if clicks >= 2 then
          M.rename(nil, session)
        end
        return
      end
    end
  end)
end

--- Routes a close-button click separately from tab selection and double-click rename.
function M.tab_close(id, clicks, button)
  if button ~= "l" or clicks ~= 1 then
    return
  end
  vim.schedule(function()
    for _, session in ipairs(M.sessions) do
      if session.id == id then
        M.close(session)
        return
      end
    end
  end)
end

--- Returns the shared session-state icon for the statusline and Herd's own session bar.
function M.symbol(session)
  return session.state == "idle" and session.unread and "✓" or symbols[session.state] or "!"
end

--- Returns compact Lualine entries for every instance.
function M.statusline()
  local parts = {}
  for _, session in ipairs(M.sessions) do
    parts[#parts + 1] = ("π%d%s"):format(session.id, M.symbol(session))
  end
  return table.concat(parts, " ")
end

--- Installs commands and mappings once; no Pi process is started until requested.
function M.setup(opts)
  options = vim.tbl_extend("force", options, opts or {})
  View.setup(options)
  if configured then
    return
  end
  configured = true
  local commands = {
    HerdNew = {
      function(cmd)
        M.new(cmd.args)
      end,
      { nargs = "?", complete = "dir" },
    },
    HerdList = { M.list },
    HerdToggle = { M.toggle },
    HerdStop = { M.stop },
    HerdClose = {
      function()
        M.close()
      end,
    },
    HerdRename = {
      function(cmd)
        M.rename(cmd.args ~= "" and cmd.args or nil)
      end,
      { nargs = "*" },
    },
    HerdAbort = { M.abort },
    HerdLayout = {
      function()
        M.layout()
      end,
    },
    HerdFloat = {
      function()
        M.layout("float")
      end,
    },
    HerdDock = {
      function()
        M.layout("split")
      end,
    },
    HerdSteer = {
      function(cmd)
        M.steer(cmd.args)
      end,
      { nargs = "*" },
    },
  }
  for name, definition in pairs(commands) do
    vim.api.nvim_create_user_command(
      name,
      definition[1],
      vim.tbl_extend("force", { desc = name .. " Pi session" }, definition[2] or {})
    )
  end
  local maps = {
    { "h", M.list, "Herd sessions" },
    { "hn", M.new, "New Pi session" },
    { "ht", M.toggle, "Toggle Herd" },
    {
      "hf",
      function()
        M.layout()
      end,
      "Float/dock Herd",
    },
    {
      "h]",
      function()
        M.cycle(1)
      end,
      "Next Pi session",
    },
    {
      "h[",
      function()
        M.cycle(-1)
      end,
      "Previous Pi session",
    },
    { "hk", M.stop, "Stop Pi session" },
    { "ha", M.abort, "Abort Pi work" },
    { "hr", M.steer, "Steer Pi" },
  }
  for _, map in ipairs(maps) do
    vim.keymap.set("n", "<leader>" .. map[1], map[2], { desc = map[3] })
  end
  vim.keymap.set("x", "<leader>hs", M.selection, { desc = "Send selected lines to Pi" })
  local group = vim.api.nvim_create_augroup("herd", { clear = true })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function()
      local session = M.active()
      if session and session.buf == vim.api.nvim_get_current_buf() then
        session.unread = false
        UI.render(session)
        refresh()
      else
        View.refresh()
      end
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      for _, session in ipairs(M.sessions) do
        session:stop()
        -- Neovim is exiting: do not wait for deferred shutdown timers.
        if session.job and session.job > 0 and not session.closed then
          pcall(vim.fn.jobstop, session.job)
        end
      end
    end,
  })
end

return M
