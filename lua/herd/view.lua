local M = {}
local views = {}
local default_mode = "float"
local ZINDEX = 40 -- Below native completion and the usual input/notification floats.

--- Returns popup dimensions that leave room for the border, winbar, and command line.
function M.geometry()
  local rows = math.max(1, vim.o.lines - vim.o.cmdheight)
  local width = math.max(1, math.min(math.floor(vim.o.columns * 0.85), vim.o.columns - 2))
  local height = math.max(1, math.min(math.floor(rows * 0.8), rows - 3))
  return {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((rows - height - 3) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)),
    border = "rounded",
    title = " Herd ",
    title_pos = "center",
    focusable = true,
    zindex = ZINDEX,
  }
end

--- Identifies our prompt buffers without filtering unrelated user buffers.
function M.is_buffer(buf)
  return vim.api.nvim_buf_is_valid(buf)
    and vim.bo[buf].filetype == "herd"
    and vim.api.nvim_buf_get_name(buf):match("^herd://pi/%d+$") ~= nil
end

--- Avoids copying Herd's private strip into an ordinary window's saved options.
local function ordinary_bar(win)
  local bar = vim.wo[win].winbar
  return bar:find("@v:lua.require'herd'.tab_click@", 1, true) and vim.go.winbar or bar
end

--- Returns the current tab's live managed view, forgetting closed/replaced windows.
local function current_view()
  local tab = vim.api.nvim_get_current_tabpage()
  local view = views[tab]
  if
    view
    and view.win
    and (not vim.api.nvim_win_is_valid(view.win) or not M.is_buffer(vim.api.nvim_win_get_buf(view.win)))
  then
    if vim.api.nvim_win_is_valid(view.win) then
      vim.wo[view.win].winbar = view.previous_bar
    end
    view.win = nil
  end
  return view
end

--- Returns this tab's selected agent buffer, including while its view is hidden.
function M.buffer()
  local view = current_view()
  if not view then
    return nil
  end
  return view.win and vim.api.nvim_win_get_buf(view.win) or view.buf
end

--- Renders a bounded session strip with the selected agent always in its visible range.
function M.bar(sessions, selected, width)
  if #sessions == 0 then
    return ""
  end
  local labels, active = {}, 1
  for i, session in ipairs(sessions) do
    labels[i] = "[π" .. session.id .. require("herd").symbol(session) .. "]"
    if session.buf == selected then
      active = i
    end
  end
  local first, last = active, active
  local used = vim.fn.strdisplaywidth(labels[active])
  local budget = math.max(0, width - 16) -- Herd label, overflow marks, and the new-session button.
  while first > 1 or last < #sessions do
    local changed = false
    if first > 1 and used + vim.fn.strdisplaywidth(labels[first - 1]) <= budget then
      first = first - 1
      used = used + vim.fn.strdisplaywidth(labels[first])
      changed = true
    end
    if last < #sessions and used + vim.fn.strdisplaywidth(labels[last + 1]) <= budget then
      last = last + 1
      used = used + vim.fn.strdisplaywidth(labels[last])
      changed = true
    end
    if not changed then
      break
    end
  end
  local parts = { "%#TabLine# Herd ", first > 1 and "‹ " or "" }
  for i = first, last do
    parts[#parts + 1] = (i == active and "%#TabLineSel#" or "%#TabLine#")
      .. "%"
      .. sessions[i].id
      .. "@v:lua.require'herd'.tab_click@"
      .. labels[i]
      .. "%T"
  end
  parts[#parts + 1] = "%#TabLine#" .. (last < #sessions and " ›" or "") .. " %0@v:lua.require'herd'.tab_click@[+]%T%*"
  return table.concat(parts)
end

--- Refreshes only Herd's own window-local bars, restoring a window reused for code.
function M.refresh()
  local sessions = require("herd").sessions
  for tab, view in pairs(views) do
    if not vim.api.nvim_tabpage_is_valid(tab) then
      views[tab] = nil
    elseif view.win and vim.api.nvim_win_is_valid(view.win) then
      local buf = vim.api.nvim_win_get_buf(view.win)
      if M.is_buffer(buf) then
        view.buf = buf
        local bar = M.bar(sessions, buf, vim.api.nvim_win_get_width(view.win))
        if vim.wo[view.win].winbar ~= bar then
          vim.wo[view.win].winbar = bar
        end
      else
        vim.wo[view.win].winbar = view.previous_bar
        view.win = nil
      end
    end
  end
  -- Neovim can inherit window-local options from the previous window/buffer.
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if not M.is_buffer(vim.api.nvim_win_get_buf(win)) then
      local clean = ordinary_bar(win)
      if vim.wo[win].winbar ~= clean then
        vim.wo[win].winbar = clean
      end
    end
  end
  vim.cmd.redrawstatus()
end

--- Finds a normal code window in this tab, even when a picker currently has focus.
local function normal_window(preferred)
  if
    preferred
    and vim.api.nvim_win_is_valid(preferred)
    and vim.api.nvim_win_get_tabpage(preferred) == vim.api.nvim_get_current_tabpage()
    and vim.api.nvim_win_get_config(preferred).relative == ""
  then
    return preferred
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win).relative == "" then
      return win
    end
  end
end

--- Opens or reuses this tab's Herd view without selecting a window in another tab.
function M.show(buf)
  local tab = vim.api.nvim_get_current_tabpage()
  local view = current_view() or { mode = default_mode }
  views[tab] = view
  view.buf = buf
  if not view.win then
    local base = normal_window(vim.api.nvim_get_current_win())
    view.previous_bar = ordinary_bar(base)
    view.return_win = base
    if view.mode == "float" then
      view.win = vim.api.nvim_open_win(buf, true, M.geometry())
    else
      view.win = vim.api.nvim_open_win(
        buf,
        true,
        { win = base, split = "right", width = math.max(1, math.floor(vim.o.columns * 0.4)) }
      )
    end
    vim.wo[view.win].wrap = true
    vim.wo[view.win].number = false
    vim.wo[view.win].relativenumber = false
  else
    vim.api.nvim_set_current_win(view.win)
    if vim.api.nvim_win_get_buf(view.win) ~= buf then
      vim.api.nvim_win_set_buf(view.win, buf)
    end
  end
  M.refresh()
  return view.win
end

--- Hides only the current tab's managed view; buffers and Pi processes remain alive.
function M.hide()
  local view = current_view()
  if not view or not view.win then
    return
  end
  local win = view.win
  view.win = nil
  vim.cmd.stopinsert()
  local normal_windows = 0
  for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(candidate).relative == "" then
      normal_windows = normal_windows + 1
    end
  end
  if vim.api.nvim_win_get_config(win).relative == "" and normal_windows == 1 then
    -- Neovim cannot close its last normal window. Leave a code/scratch buffer instead.
    vim.wo[win].winbar = view.previous_bar
    local previous = view.return_win
    local buf = previous and vim.api.nvim_win_is_valid(previous) and vim.api.nvim_win_get_buf(previous)
    vim.api.nvim_win_set_buf(win, buf and not M.is_buffer(buf) and buf or vim.api.nvim_create_buf(true, false))
  else
    vim.api.nvim_win_close(win, false)
  end
  if view.return_win and vim.api.nvim_win_is_valid(view.return_win) then
    vim.api.nvim_set_current_win(view.return_win)
  end
end

--- Changes presentation in place, preserving the session, buffer, and prompt draft.
function M.layout(mode, buf)
  local view = current_view()
  mode = mode or (view and view.mode == "float" and "split" or "float")
  if mode ~= "float" and mode ~= "split" then
    return
  end
  if not view or not view.win then
    local tab = vim.api.nvim_get_current_tabpage()
    views[tab] = view or {}
    views[tab].mode = mode
    return M.show(buf)
  end
  if view.mode ~= mode then
    if mode == "float" then
      local normal = 0
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_config(win).relative == "" then
          normal = normal + 1
        end
      end
      if normal == 1 then
        -- Keep one normal window when the user closed all other code windows.
        view.return_win =
          vim.api.nvim_open_win(vim.api.nvim_create_buf(true, false), false, { win = view.win, split = "left" })
      end
      vim.api.nvim_win_set_config(view.win, M.geometry())
    else
      local base = normal_window(view.return_win)
      vim.api.nvim_win_set_config(
        view.win,
        { relative = "", win = base, split = "right", width = math.max(1, math.floor(vim.o.columns * 0.4)) }
      )
    end
    view.mode = mode
  end
  vim.api.nvim_set_current_win(view.win)
  M.refresh()
  return view.win
end

--- Configures presentation and resize handling without launching an agent.
function M.setup(opts)
  if opts and (opts.view == "float" or opts.view == "split") then
    default_mode = opts.view
  end
  local group = vim.api.nvim_create_augroup("herd_views", { clear = true })
  vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    group = group,
    callback = function()
      for _, view in pairs(views) do
        if view.win and vim.api.nvim_win_is_valid(view.win) and view.mode == "float" then
          vim.api.nvim_win_set_config(view.win, M.geometry())
        end
      end
      M.refresh()
    end,
  })
  vim.api.nvim_create_autocmd("TabClosed", { group = group, callback = M.refresh })
end

return M
