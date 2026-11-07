-- Run from the repository root: nvim --headless --clean -u NONE -l tests/herd/run.lua
-- No plugins, model calls, user sessions, or external test frameworks are needed.
local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
local saved_env = {}
for _, name in ipairs({ "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME", "HERD_TEST_LOG" }) do
  saved_env[name] = vim.env[name] or false
  vim.env[name] = tmp .. "/" .. name
end
vim.fn.writefile({}, vim.env.HERD_TEST_LOG)
local herd = require("herd")
local UI = require("herd.ui")
local View = require("herd.view")
local checks = 0
local old_notify = vim.notify
vim.notify = function() end

--- Fails with a focused assertion label and records successful checks.
local function check(value, label)
  assert(value, label)
  checks = checks + 1
end

--- Waits for a deterministic subprocess/UI state without fixed sleeps.
local function wait(predicate, label)
  check(vim.wait(5000, predicate, 10), label)
end

--- Returns the buffer text after applying pending transcript updates.
local function text(session)
  UI.render(session)
  return table.concat(vim.api.nvim_buf_get_lines(session.buf, 0, -1, false), "\n")
end

--- Exercises presentation changes against real Neovim buffers/windows and fake RPC children.
local function run()
  vim.g.mapleader = " "
  herd.setup({
    command = { vim.v.progpath, "--headless", "--clean", "-u", "NONE", "-l", root .. "/tests/herd/fake_pi.lua" },
  })
  local code = vim.api.nvim_get_current_win()
  local code_buf = vim.api.nvim_get_current_buf()
  vim.wo[code].winbar = "Main code"
  vim.o.tabline = "Main file bar"
  vim.cmd("vsplit")
  local other_code = vim.api.nvim_get_current_win()
  local layout = vim.fn.winlayout()
  local session = herd.new(tmp)
  wait(function()
    return session.ready
  end, "first RPC process ready")
  local popup = vim.api.nvim_get_current_win()
  local job = session.job
  check(vim.api.nvim_win_get_config(popup).relative == "editor", "popup is the default")
  check(vim.api.nvim_win_get_config(popup).zindex < 50, "popup is below standard dialog surfaces")
  check(vim.deep_equal(vim.fn.winlayout(), layout), "popup preserves normal code layout")
  check(
    vim.api.nvim_win_get_buf(code) == code_buf and vim.wo[code].winbar == "Main code",
    "code buffer and winbar unchanged"
  )
  check(vim.o.tabline == "Main file bar", "global file bar unchanged")
  check(vim.bo[session.buf].buflisted, "Herd buffers still support normal buffer navigation")

  local draft = "You> saved draft"
  local last = vim.api.nvim_buf_line_count(session.buf)
  vim.api.nvim_buf_set_lines(session.buf, last - 1, last, false, { draft })
  local second = herd.new(tmp)
  wait(function()
    return second.ready
  end, "second RPC process ready")
  check(vim.api.nvim_get_current_win() == popup, "new sessions reuse the same view")
  check(vim.api.nvim_win_get_buf(popup) == second.buf, "view switches to selected session buffer")
  herd.cycle(-1)
  check(
    vim.api.nvim_get_current_win() == popup and vim.api.nvim_win_get_buf(popup) == session.buf,
    "cycling reuses the view"
  )
  check(vim.api.nvim_buf_get_lines(session.buf, -2, -1, false)[1] == draft, "session switch preserves prompt draft")
  local bar = vim.wo[popup].winbar
  local evaluated = vim.api.nvim_eval_statusline(bar, { winid = popup, use_winbar = true, highlights = true })
  check(
    evaluated.str:find("π1", 1, true) and evaluated.str:find("π2", 1, true) and evaluated.str:find("[+]", 1, true),
    "independent session bar renders tabs and new button"
  )
  check(bar:find("TabLineSel", 1, true), "selected session is highlighted")

  herd.layout("split")
  check(vim.api.nvim_get_current_win() == popup, "docking preserves window identity")
  check(vim.api.nvim_win_get_config(popup).relative == "", "docked view is a normal split")
  herd.layout("float")
  check(
    vim.api.nvim_get_current_win() == popup and vim.api.nvim_win_get_config(popup).relative == "editor",
    "detach converts the same window to a popup"
  )
  check(session.job == job and session.ready and not session.closed, "dock/float preserves RPC process")
  check(vim.api.nvim_buf_get_lines(session.buf, -2, -1, false)[1] == draft, "dock/float preserves draft")

  vim.api.nvim_eval("v:lua.require'herd'.tab_click(" .. second.id .. ",1,'l','')")
  wait(function()
    return vim.api.nvim_win_get_buf(popup) == second.buf
  end, "session-tab click selects its buffer")
  local selected = herd.active()
  herd.tab_click(session.id, 1, "r")
  vim.wait(20)
  check(herd.active() == selected, "non-left clicks do not switch sessions")
  local old_new, requested = herd.new, false
  herd.new = function()
    requested = true
  end
  herd.tab_click(0, 1, "l")
  wait(function()
    return requested
  end, "new-session tab routes to creation")
  herd.new = old_new

  local original_input = vim.ui.input
  local answered = false
  vim.ui.input = function(opts, callback)
    answered = true
    callback("root")
  end
  second:receive({ type = "extension_ui_request", id = "input", method = "input", title = "Fixture" })
  check(answered and not second.dialogs.input, "RPC input requests still reach the native input backend")
  vim.ui.input = original_input
  second:receive({
    type = "extension_ui_request",
    id = "edit",
    method = "editor",
    title = "Input",
    prefill = "one\ntwo",
  })
  local editor_win = vim.api.nvim_get_current_win()
  check(
    vim.api.nvim_win_get_config(editor_win).zindex > vim.api.nvim_win_get_config(popup).zindex,
    "multiline input is above Herd"
  )
  vim.fn.maparg("<C-s>", "n", false, true).callback()
  wait(function()
    return not second.dialogs.edit
  end, "multiline dialog can complete")

  herd.show(session)
  herd.toggle()
  check(not vim.api.nvim_win_is_valid(popup) and session.ready and session.job == job, "hiding closes only the view")
  check(vim.deep_equal(vim.fn.winlayout(), layout), "hide restores exact code layout")
  check(vim.api.nvim_get_current_win() == other_code, "hide returns to its original code window")
  check(herd.send(session, "hello"), "hidden agent accepts prompts")
  wait(function()
    return session.unread
  end, "hidden agent completion is tracked")
  check(herd.statusline():find("✓", 1, true), "hidden progress remains on main statusline")
  herd.toggle()
  popup = vim.api.nvim_get_current_win()
  check(text(session):find("Final response: hello", 1, true), "transcript survives hide/show")

  vim.o.columns = 48
  vim.o.lines = 16
  vim.api.nvim_exec_autocmds("VimResized", {})
  local geometry = vim.api.nvim_win_get_config(popup)
  check(geometry.width + 2 <= vim.o.columns and geometry.height + 3 <= vim.o.lines, "resized popup fits terminal")
  local many = {}
  for i = 1, 20 do
    many[i] = { id = i, buf = i, state = "running" }
  end
  local narrow = View.bar(many, 20, 30)
  local display = vim.api.nvim_eval_statusline(narrow, { maxwidth = 30 }).str
  check(
    display:find("π20", 1, true) and display:find("[+]", 1, true) and display:find("‹", 1, true),
    "overflow keeps selected agent and controls accessible"
  )

  local specs = dofile(root .. "/lua/plugins/herd.lua")
  local args, calls = { code_buf, session.buf }, 0
  local opts = {
    options = {
      custom_filter = function(buf, buffers)
        calls = calls + 1
        check(buffers == args, "previous filter receives buffer list")
        return buf ~= code_buf
      end,
    },
  }
  specs[1].opts({}, opts)
  check(
    not opts.options.custom_filter(session.buf, args) and calls == 0,
    "Herd filter excludes only agent buffers before user filter"
  )
  check(not opts.options.custom_filter(code_buf, args) and calls == 1, "existing filter exclusions preserved")
  local plain = vim.api.nvim_create_buf(true, false)
  check(opts.options.custom_filter(plain, args), "ordinary buffers remain visible")
  check(specs[2].init == nil, "LazyVim Lualine init remains inherited")

  local first_tab = vim.api.nvim_get_current_tabpage()
  vim.cmd("tabnew")
  local second_tab = vim.api.nvim_get_current_tabpage()
  herd.show(second)
  local tab_popup = vim.api.nvim_get_current_win()
  check(tab_popup ~= popup and vim.api.nvim_win_get_tabpage(tab_popup) == second_tab, "each tab has its own view")
  UI.hide()
  check(
    not vim.api.nvim_win_is_valid(tab_popup) and vim.api.nvim_win_is_valid(popup),
    "hide does not close another tab's view"
  )
  vim.api.nvim_set_current_tabpage(first_tab)
  vim.api.nvim_set_current_win(other_code)
  check(herd.active() == session, "code windows resolve the current tab's agent, not another tab's selection")
  herd.layout("split")
  check(
    vim.api.nvim_win_get_buf(popup) == session.buf,
    "layout changes from code target the current tab's selected agent"
  )
  herd.layout("float")
  herd.show(session)
  check(vim.api.nvim_get_current_win() == popup, "original tab reuses its own view")
  UI.hide()
  herd.layout("split")
  local docked = vim.api.nvim_get_current_win()
  -- Replacing a Herd view with code must remove its private winbar.
  vim.api.nvim_win_set_buf(docked, plain)
  View.refresh()
  check(
    not vim.wo[docked].winbar:find("tab_click", 1, true),
    "reused code windows do not retain Herd's session bar: " .. vim.wo[docked].winbar
  )
  check(
    vim.fn.exists(":HerdLayout") == 2 and vim.fn.exists(":HerdFloat") == 2 and vim.fn.exists(":HerdDock") == 2,
    "layout commands registered"
  )
  check(vim.fn.maparg("<leader>hf", "n") ~= "", "layout keymap registered")
  herd.setup({ view = "split" })
  vim.cmd("tabnew")
  herd.show(session)
  local sole = vim.api.nvim_get_current_win()
  check(vim.api.nvim_win_get_config(sole).relative == "", "configured split default applies to new tab views")
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= sole then
      vim.api.nvim_win_close(win, true)
    end
  end
  herd.layout("float")
  check(vim.api.nvim_win_get_config(sole).relative == "editor", "last normal Herd window can detach safely")
  UI.hide()
  check(
    #vim.api.nvim_tabpage_list_wins(0) == 1 and session.ready,
    "last-window fallback keeps Neovim and the agent alive"
  )
end

local ok, err = xpcall(run, debug.traceback)
for _, session in ipairs(herd.sessions) do
  UI.cancel_dialogs(session)
  session:stop()
end
vim.wait(5000, function()
  for _, session in ipairs(herd.sessions) do
    if not session.closed then
      return false
    end
  end
  return true
end, 10)
vim.notify = old_notify
for name, value in pairs(saved_env) do
  vim.env[name] = value or nil
end
vim.fn.delete(tmp, "rf")
if not ok then
  error(err)
end
io.stdout:write(("PASS Herd workspace: %d checks\n"):format(checks))
vim.cmd("qa!")
