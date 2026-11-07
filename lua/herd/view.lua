local M = {}
local views = {}
local default_mode = "float"
local ZINDEX = 40 -- Below native completion and the usual input/notification floats.
local HIGHLIGHT = "Normal:HerdNormal,NormalNC:HerdNormal,WinBar:HerdBar,WinBarNC:HerdBar"

--- Builds theme-relative colors without depending on Lazy's internal window implementation.
local function colors()
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local floating = vim.api.nvim_get_hl(0, { name = "NormalFloat", link = false })
  local bg = floating.bg or normal.bg or 0x17171F
  if bg == normal.bg then
    bg = math.floor(math.floor(bg / 65536) * 0.9) * 65536
      + math.floor((math.floor(bg / 256) % 256) * 0.9) * 256
      + math.floor((bg % 256) * 0.9)
  end
  local function lighter(amount)
    local r, g, b = math.floor(bg / 65536), math.floor(bg / 256) % 256, bg % 256
    return math.floor(r + (255 - r) * amount) * 65536
      + math.floor(g + (255 - g) * amount) * 256
      + math.floor(b + (255 - b) * amount)
  end
  local fg = floating.fg or normal.fg or 0xC0CAF5
  vim.api.nvim_set_hl(0, "HerdNormal", { bg = bg, fg = fg })
  vim.api.nvim_set_hl(0, "HerdBar", { bg = bg, fg = fg })
  vim.api.nvim_set_hl(0, "HerdTab", { bg = lighter(0.04), fg = fg })
  vim.api.nvim_set_hl(0, "HerdTabActive", { bg = lighter(0.10), fg = fg, bold = true })
  vim.api.nvim_set_hl(0, "HerdBackdrop", { bg = 0 })
end

--- Closes only the generated backdrop owned by this view.
local function clear_backdrop(view)
  local win, buf = view.backdrop_win, view.backdrop_buf
  view.backdrop_win, view.backdrop_buf = nil, nil
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end

--- Matches Lazy's dimmed backdrop while leaving input and completion surfaces above Herd.
local function backdrop(view)
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  if view.mode ~= "float" or not vim.o.termguicolors or not normal.bg then
    clear_backdrop(view)
    return
  end
  if not view.backdrop_win or not vim.api.nvim_win_is_valid(view.backdrop_win) then
    view.backdrop_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[view.backdrop_buf].bufhidden = "wipe"
    view.backdrop_win = vim.api.nvim_win_call(view.win, function()
      return vim.api.nvim_open_win(view.backdrop_buf, false, {
        relative = "editor",
        row = 0,
        col = 0,
        width = vim.o.columns,
        height = vim.o.lines,
        style = "minimal",
        border = "none",
        focusable = false,
        mouse = false,
        zindex = ZINDEX - 1,
      })
    end)
    vim.wo[view.backdrop_win].winbar = ""
    vim.wo[view.backdrop_win].winhighlight = "Normal:HerdBackdrop"
    vim.wo[view.backdrop_win].winblend = 60
  else
    vim.api.nvim_win_set_config(view.backdrop_win, { width = vim.o.columns, height = vim.o.lines })
  end
end

--- Returns borderless popup dimensions with room for its window-local session bar.
function M.geometry()
  local rows = math.max(1, vim.o.lines - vim.o.cmdheight)
  local width = math.max(1, math.min(math.floor(vim.o.columns * 0.85), vim.o.columns - 2))
  local height = math.max(1, math.min(math.floor(rows * 0.8), rows - 3))
  return {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((rows - height - 1) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    border = "none",
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

--- Restores non-Herd highlighting when Neovim inherits our window-local options.
local function ordinary_highlight(win)
  local value = vim.wo[win].winhighlight
  return value == HIGHLIGHT and vim.go.winhighlight or value
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
      vim.wo[view.win].winhighlight = view.previous_highlight
    end
    clear_backdrop(view)
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
  local herd = require("herd")
  for i, session in ipairs(sessions) do
    local name = herd.label(session)
    local limit = math.max(3, math.min(24, width - 19))
    if vim.fn.strdisplaywidth(name) > limit then
      while vim.fn.strdisplaywidth(name .. "…") > limit do
        name = vim.fn.strcharpart(name, 0, vim.fn.strchars(name) - 1)
      end
      name = name .. "…"
    end
    local label = "  " .. herd.symbol(session) .. " π " .. name
    local padding = math.max(1, math.min(20, width - 16) - vim.fn.strdisplaywidth(label))
    labels[i] = label .. string.rep(" ", padding)
    if session.buf == selected then
      active = i
    end
  end
  local first, last = active, active
  local used = vim.fn.strdisplaywidth(labels[active]) + 3
  local budget = math.max(0, width - 16) -- Herd label, overflow marks, and the new-session button.
  while first > 1 or last < #sessions do
    local changed = false
    if first > 1 and used + vim.fn.strdisplaywidth(labels[first - 1]) + 4 <= budget then
      first = first - 1
      used = used + vim.fn.strdisplaywidth(labels[first]) + 4
      changed = true
    end
    if last < #sessions and used + vim.fn.strdisplaywidth(labels[last + 1]) + 4 <= budget then
      last = last + 1
      used = used + vim.fn.strdisplaywidth(labels[last]) + 4
      changed = true
    end
    if not changed then
      break
    end
  end
  local parts = { "%#HerdBar# Herd ", first > 1 and "‹ " or "" }
  for i = first, last do
    if i > first then
      parts[#parts + 1] = "%#HerdBar#|"
    end
    parts[#parts + 1] = (i == active and "%#HerdTabActive#" or "%#HerdTab#")
      .. "%"
      .. sessions[i].id
      .. "@v:lua.require'herd'.tab_click@"
      .. labels[i]:gsub("%%", "%%%%")
      .. "%T%"
      .. sessions[i].id
      .. "@v:lua.require'herd'.tab_close@ × %T"
  end
  parts[#parts + 1] = "%#HerdBar#" .. (last < #sessions and " ›" or "") .. " %0@v:lua.require'herd'.tab_click@ + %T%*"
  return table.concat(parts)
end

--- Refreshes only Herd's own window-local bars, restoring a window reused for code.
function M.refresh()
  local sessions = require("herd").sessions
  for tab, view in pairs(views) do
    if not vim.api.nvim_tabpage_is_valid(tab) then
      clear_backdrop(view)
      views[tab] = nil
    elseif view.win and vim.api.nvim_win_is_valid(view.win) then
      local buf = vim.api.nvim_win_get_buf(view.win)
      if M.is_buffer(buf) then
        view.buf = buf
        vim.wo[view.win].winhighlight = HIGHLIGHT
        backdrop(view)
        local bar = M.bar(sessions, buf, vim.api.nvim_win_get_width(view.win))
        if vim.wo[view.win].winbar ~= bar then
          vim.wo[view.win].winbar = bar
        end
      else
        vim.wo[view.win].winbar = view.previous_bar
        vim.wo[view.win].winhighlight = view.previous_highlight
        clear_backdrop(view)
        view.win = nil
      end
    else
      clear_backdrop(view)
    end
  end
  -- Neovim can inherit window-local options from the previous window/buffer.
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if not M.is_buffer(vim.api.nvim_win_get_buf(win)) then
      local clean = ordinary_bar(win)
      if vim.wo[win].winbar ~= clean then
        vim.wo[win].winbar = clean
      end
      local highlight = ordinary_highlight(win)
      if vim.wo[win].winhighlight ~= highlight then
        vim.wo[win].winhighlight = highlight
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
    view.previous_highlight = ordinary_highlight(base)
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
  clear_backdrop(view)
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
    vim.wo[win].winhighlight = view.previous_highlight
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

--- Replaces or closes every managed view of a removed session without leaving empty popups.
function M.remove(buf, replacement)
  for tab, view in pairs(views) do
    if view.buf == buf then
      view.buf = replacement
      local win = view.win
      if win and vim.api.nvim_win_is_valid(win) then
        if replacement then
          vim.api.nvim_win_set_buf(win, replacement)
        else
          view.win = nil
          clear_backdrop(view)
          local normal = 0
          for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
            if vim.api.nvim_win_get_config(candidate).relative == "" then
              normal = normal + 1
            end
          end
          if vim.api.nvim_win_get_config(win).relative == "" and normal == 1 then
            vim.wo[win].winbar = view.previous_bar
            vim.wo[win].winhighlight = view.previous_highlight
            vim.api.nvim_win_set_buf(win, vim.api.nvim_create_buf(true, false))
          else
            vim.api.nvim_win_close(win, false)
          end
        end
      end
    end
  end
  M.refresh()
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
  colors()
  local group = vim.api.nvim_create_augroup("herd_views", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      colors()
      M.refresh()
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function()
      vim.schedule(M.refresh)
    end,
  })
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
