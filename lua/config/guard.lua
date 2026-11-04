-- Optional overrides, set before setup():
-- vim.g.tool_guard = { ignore = { "docker" }, cache_ttl = 24 * 60 * 60 }
local M = {}

-- Increment when the dependency manifest or cache schema changes.
local CACHE_VERSION = 1
local CACHE_TTL = 24 * 60 * 60
local NOTIFICATION_ID = "tool-guard"
local STARTUP_DELAY_MS = 1500
local SLOW_CHECK_MS = 2000

local core_tools = {
  {
    id = "git",
    commands = { "git" },
    label = "git",
    reason = "plugin installation and updates",
    source = "LazyVim core",
    required = true,
  },
  {
    id = "rg",
    commands = { "rg" },
    label = "rg (ripgrep)",
    reason = "fast project search",
    source = "LazyVim core",
    required = true,
  },
  {
    id = "fd",
    commands = { "fd", "fdfind" },
    label = "fd",
    reason = "fast file discovery",
    source = "LazyVim core",
    required = true,
  },
  {
    id = "curl",
    commands = { "curl" },
    label = "curl",
    reason = "plugin and tool downloads",
    source = "LazyVim core",
    required = true,
  },
  {
    id = "tar",
    commands = { "tar" },
    label = "tar",
    reason = "archive extraction",
    source = "LazyVim core",
    required = true,
  },
  {
    id = "unzip",
    commands = { "unzip" },
    label = "unzip",
    reason = "archive extraction",
    source = "LazyVim core",
    required = true,
  },
  {
    id = "tree-sitter",
    commands = { "tree-sitter" },
    label = "tree-sitter CLI",
    reason = "parser generation and updates",
    source = "LazyVim core",
    required = true,
  },
  {
    id = "c-compiler",
    commands = { "cc", "gcc", "clang", "cl" },
    label = "C compiler",
    reason = "native plugin and parser builds",
    source = "LazyVim core",
    required = true,
  },
  {
    id = "fzf",
    commands = { "fzf" },
    label = "fzf",
    reason = "fuzzy finding",
    source = "LazyVim core",
  },
  {
    id = "lazygit",
    commands = { "lazygit" },
    label = "lazygit",
    reason = "interactive Git integration",
    source = "LazyVim core",
  },
  {
    id = "make",
    commands = { "make", "gmake", "nmake" },
    label = "make",
    reason = "native plugin builds",
    source = "LazyVim core",
  },
}

local extra_tools = {
  ["lazyvim.plugins.extras.lang.clangd"] = {
    {
      id = "clangd",
      commands = { "clangd" },
      label = "clangd",
      reason = "C and C++ language support",
    },
  },
  ["lazyvim.plugins.extras.lang.docker"] = {
    {
      id = "docker",
      commands = { "docker" },
      label = "docker",
      reason = "Docker project workflows",
    },
  },
  ["lazyvim.plugins.extras.lang.go"] = {
    {
      id = "go",
      commands = { "go" },
      label = "Go toolchain",
      reason = "Go builds, tests, and tooling",
    },
  },
  ["lazyvim.plugins.extras.lang.markdown"] = {
    {
      id = "node",
      commands = { "node" },
      label = "Node.js",
      reason = "Markdown preview tooling",
    },
  },
  ["lazyvim.plugins.extras.lang.nix"] = {
    {
      id = "nix",
      commands = { "nix" },
      label = "nix",
      reason = "Nix evaluation and project tooling",
    },
  },
  ["lazyvim.plugins.extras.lang.python"] = {
    {
      id = "python",
      commands = { "python3", "python" },
      label = "Python",
      reason = "Python project tooling",
    },
  },
  ["lazyvim.plugins.extras.lang.terraform"] = {
    {
      id = "terraform",
      commands = { "terraform" },
      label = "terraform",
      reason = "Terraform validation and workflows",
    },
  },
  ["lazyvim.plugins.extras.lang.twig"] = {
    {
      id = "php",
      commands = { "php" },
      label = "PHP",
      reason = "Twig formatter and project tooling",
    },
  },
  ["lazyvim.plugins.extras.lang.typescript"] = {
    {
      id = "node",
      commands = { "node" },
      label = "Node.js",
      reason = "TypeScript language tooling",
    },
    {
      id = "npm",
      commands = { "npm" },
      label = "npm",
      reason = "TypeScript project tooling",
    },
    {
      id = "tsx",
      commands = { "tsx" },
      label = "tsx",
      reason = "TypeScript file execution",
    },
  },
  ["lazyvim.plugins.extras.lang.zig"] = {
    {
      id = "zig",
      commands = { "zig" },
      label = "Zig toolchain",
      reason = "Zig builds and language tooling",
    },
  },
}

local function joinpath(...)
  return vim.fs.joinpath(...)
end

local function read_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and table.concat(lines, "\n") or ""
end

local function read_json(path)
  local contents = read_file(path)
  if contents == "" then
    return {}
  end
  local ok, decoded = pcall(vim.json.decode, contents)
  return ok and type(decoded) == "table" and decoded or {}
end

local function list_to_set(values)
  local result = {}
  if type(values) ~= "table" then
    return result
  end
  for key, value in pairs(values) do
    if type(key) == "number" and type(value) == "string" then
      result[value] = true
    elseif type(key) == "string" and value then
      result[key] = true
    end
  end
  return result
end

local function settings()
  local configured = type(vim.g.tool_guard) == "table" and vim.g.tool_guard or {}
  return {
    cache_ttl = tonumber(configured.cache_ttl) or CACHE_TTL,
    ignore = list_to_set(configured.ignore),
  }
end

local function enabled_extras()
  local config = read_json(joinpath(vim.fn.stdpath("config"), "lazyvim.json"))
  local extras = {}
  for _, extra in ipairs(config.extras or {}) do
    if type(extra) == "string" then
      extras[extra] = true
    end
  end
  return extras
end

local function add_source(values, value)
  if not vim.tbl_contains(values, value) then
    values[#values + 1] = value
  end
end

local function add_tool(tools, tool, ignore)
  if ignore[tool.id] or ignore[tool.label] then
    return
  end
  for _, command in ipairs(tool.commands or {}) do
    if ignore[command] then
      return
    end
  end

  local existing = tools[tool.id]
  if existing then
    existing.required = existing.required or tool.required or false
    for _, command in ipairs(tool.commands or {}) do
      add_source(existing.commands, command)
    end
    if tool.available ~= nil then
      existing.available = existing.available == true or tool.available
    end
    add_source(existing.reasons, tool.reason)
    add_source(existing.sources, tool.source)
    return
  end

  tools[tool.id] = {
    id = tool.id,
    commands = tool.commands or {},
    label = tool.label,
    reasons = { tool.reason },
    sources = { tool.source },
    required = tool.required or false,
    available = tool.available,
  }
end

local function executable_available(commands)
  for _, command in ipairs(commands) do
    if vim.fn.executable(vim.fn.expand(command)) == 1 then
      return true
    end
  end
  return false
end

local function sorted_keys(values)
  local result = {}
  for value in pairs(values) do
    result[#result + 1] = value
  end
  table.sort(result)
  return result
end

local function ensure_installed(plugin_name)
  local ok, lazyvim = pcall(require, "lazyvim.util")
  if not ok then
    return {}
  end
  local opts = lazyvim.opts(plugin_name)
  return type(opts.ensure_installed) == "table" and opts.ensure_installed or {}
end

local function add_mason_package(packages, package, source)
  if type(package) ~= "string" or package == "" then
    return
  end
  packages[package] = packages[package] or {}
  add_source(packages[package], source)
end

local function desired_mason_packages()
  local packages = {}

  for _, package in ipairs(ensure_installed("mason.nvim")) do
    add_mason_package(packages, package, "mason.nvim")
  end

  local lsp_mapping = {}
  local mappings_ok, mappings = pcall(function()
    return require("mason-lspconfig.mappings").get_mason_map()
  end)
  if mappings_ok then
    lsp_mapping = mappings.lspconfig_to_package or {}
  end
  for _, server in ipairs(ensure_installed("mason-lspconfig.nvim")) do
    add_mason_package(packages, lsp_mapping[server] or server, "mason-lspconfig.nvim")
  end

  for _, adapter in ipairs(ensure_installed("mason-nvim-dap.nvim")) do
    add_mason_package(packages, adapter, "mason-nvim-dap.nvim")
  end

  return packages
end

local function add_mason_tools(tools, ignore)
  local registry_ok, registry = pcall(require, "mason-registry")
  if not registry_ok then
    return
  end

  for package, sources in pairs(desired_mason_packages()) do
    local package_ok, mason_package = pcall(function()
      return registry.has_package(package) and registry.get_package(package) or nil
    end)
    if package_ok and mason_package then
      add_tool(tools, {
        id = package,
        commands = {},
        label = package,
        reason = "configured package is not installed",
        source = table.concat(sources, ", "),
        available = mason_package:is_installed() or mason_package:is_installing(),
      }, ignore)
    end
  end
end

local function is_dotnet_project()
  for _, pattern in ipairs({ "*.csproj", "*.fsproj", "*.sln", "global.json" }) do
    if #vim.fn.glob(joinpath(vim.fn.getcwd(), pattern), false, true) > 0 then
      return true
    end
  end
  return false
end

local function add_custom_tools(tools, ignore)
  local is_windows = vim.uv.os_uname().sysname == "Windows_NT"
  if not is_windows then
    add_tool(tools, {
      id = "bash",
      commands = { "bash" },
      label = "bash",
      reason = "tool installers and shell integrations",
      source = "LazyVim ecosystem",
    }, ignore)
  end

  local is_linux = vim.fn.has("linux") == 1
  local is_mac = vim.fn.has("mac") == 1
  local is_nixos = vim.fn.filereadable("/etc/NIXOS") == 1
  local whisper_command = "whisper-stream"
  if not is_nixos and (is_linux or is_mac) then
    whisper_command = vim.fn.expand("~/bin/whisper.cpp/build/bin/whisper-stream")
  end
  add_tool(tools, {
    id = "whisper-stream",
    commands = { whisper_command },
    label = "whisper-stream",
    reason = "speech-to-text input",
    source = "whisper.nvim",
    required = true,
  }, ignore)

  if is_dotnet_project() then
    add_tool(tools, {
      id = "dotnet",
      commands = { "dotnet" },
      label = ".NET SDK",
      reason = ".NET project language tooling",
      source = "LazyVim .NET extra",
      required = true,
    }, ignore)
  end
end

local function collect_tools(ignore)
  local tools = {}
  for _, tool in ipairs(core_tools) do
    add_tool(tools, tool, ignore)
  end

  for extra in pairs(enabled_extras()) do
    for _, tool in ipairs(extra_tools[extra] or {}) do
      tool.source = extra
      add_tool(tools, tool, ignore)
    end
  end

  add_mason_tools(tools, ignore)
  add_custom_tools(tools, ignore)
  return tools
end

local function item_sort(left, right)
  return left.label:lower() < right.label:lower()
end

function M.inspect(opts)
  opts = opts or {}
  local configured = settings()
  local ignore = opts.ignore and list_to_set(opts.ignore) or configured.ignore
  local started = vim.uv.hrtime()
  local report = {
    checked = 0,
    elapsed_ms = 0,
    optional = {},
    required = {},
  }

  for _, tool in pairs(collect_tools(ignore)) do
    report.checked = report.checked + 1
    local available = tool.available
    if available == nil then
      available = executable_available(tool.commands)
    end
    if not available then
      local item = {
        id = tool.id,
        label = tool.label,
        reason = table.concat(tool.reasons, ", "),
        source = table.concat(tool.sources, ", "),
      }
      local group = tool.required and report.required or report.optional
      group[#group + 1] = item
    end
  end

  table.sort(report.required, item_sort)
  table.sort(report.optional, item_sort)
  report.elapsed_ms = math.floor((vim.uv.hrtime() - started) / 1e6)
  return report
end

local function cache_path()
  return joinpath(vim.fn.stdpath("state"), "tool-guard.json")
end

local function fingerprint(configured)
  local uname = vim.uv.os_uname()
  local version = vim.version()
  local plugin_names = {}
  local lazy_ok, lazy_config = pcall(require, "lazy.core.config")
  if lazy_ok then
    plugin_names = sorted_keys(lazy_config.plugins or {})
  end

  local ignore = sorted_keys(configured.ignore)
  local mason_packages = sorted_keys(desired_mason_packages())
  local config_root = vim.fn.stdpath("config")
  local parts = {
    tostring(CACHE_VERSION),
    read_file(joinpath(config_root, "lazy-lock.json")),
    read_file(joinpath(config_root, "lazyvim.json")),
    table.concat(plugin_names, "\n"),
    table.concat(mason_packages, "\n"),
    table.concat(ignore, "\n"),
    table.concat({ version.major, version.minor, version.patch }, "."),
    uname.sysname,
    uname.machine,
    vim.env.PATH or "",
  }
  return vim.fn.sha256(table.concat(parts, "\0"))
end

local function read_cache(key, ttl)
  local cached = read_json(cache_path())
  if cached.version ~= CACHE_VERSION or cached.key ~= key or type(cached.report) ~= "table" then
    return nil
  end
  if type(cached.checked_at) ~= "number" or os.time() - cached.checked_at > ttl then
    return nil
  end
  cached.report.cached = true
  return cached.report
end

local function write_cache(key, report)
  local path = cache_path()
  local ok, error = pcall(function()
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    local payload = vim.json.encode({
      checked_at = os.time(),
      key = key,
      report = report,
      version = CACHE_VERSION,
    })
    assert(vim.fn.writefile({ payload }, path) == 0, "cache write failed")
  end)
  return ok, error
end

local function format_items(title, items)
  if #items == 0 then
    return nil
  end
  local lines = { title }
  for _, item in ipairs(items) do
    lines[#lines + 1] = ("• %s — %s (%s)"):format(item.label, item.reason, item.source)
  end
  return table.concat(lines, "\n")
end

function M.format(report)
  local sections = {}
  local required = format_items("Required", report.required or {})
  local optional = format_items("Optional", report.optional or {})
  if required then
    sections[#sections + 1] = required
  end
  if optional then
    sections[#sections + 1] = optional
  end
  return table.concat(sections, "\n\n")
end

local function hide_spinner()
  if _G.Snacks and Snacks.notifier then
    pcall(Snacks.notifier.hide, NOTIFICATION_ID)
  end
end

local function start_spinner()
  if not (_G.Snacks and Snacks.notifier) then
    return function() end
  end

  local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local frame = 0
  local timer = vim.uv.new_timer()
  local function render()
    frame = frame % #frames + 1
    vim.notify("Checking plugin tool dependencies…", vim.log.levels.INFO, {
      id = NOTIFICATION_ID,
      title = "Tool Guard",
      timeout = false,
      opts = function(notification)
        notification.icon = frames[frame]
      end,
    })
  end

  render()
  timer:start(80, 80, vim.schedule_wrap(render))
  return function()
    timer:stop()
    timer:close()
  end
end

local function notify_report(report, quiet_if_ok)
  local missing = #(report.required or {}) + #(report.optional or {})
  if missing == 0 then
    hide_spinner()
    if report.cache_error then
      vim.notify("Tool check completed, but its cache could not be written.", vim.log.levels.WARN, {
        id = NOTIFICATION_ID,
        title = "Tool Guard",
      })
    elseif not quiet_if_ok then
      vim.notify(
        ("All %d checked tools are available%s."):format(report.checked or 0, report.cached and " (cached)" or ""),
        vim.log.levels.INFO,
        {
          id = NOTIFICATION_ID,
          title = "Tool Guard",
        }
      )
    end
    return
  end

  local message = M.format(report)
  local suffix = {}
  if report.cached then
    suffix[#suffix + 1] = "cached"
  end
  if (report.elapsed_ms or 0) > SLOW_CHECK_MS then
    suffix[#suffix + 1] = ("slow check: %d ms"):format(report.elapsed_ms)
  end
  if report.cache_error then
    suffix[#suffix + 1] = "cache write failed"
  end
  if #suffix > 0 then
    message = message .. "\n\n" .. table.concat(suffix, ", ")
  end
  message = message .. "\n\nRun :GuardTools! to refresh."

  vim.notify(message, #(report.required or {}) > 0 and vim.log.levels.WARN or vim.log.levels.INFO, {
    id = NOTIFICATION_ID,
    title = "Missing tools",
  })
end

function M.check(opts)
  opts = opts or {}
  local configured = settings()
  local key = fingerprint(configured)
  if not opts.force then
    local cached = read_cache(key, configured.cache_ttl)
    if cached then
      if opts.notify ~= false then
        notify_report(cached, opts.quiet_if_ok)
      end
      if opts.on_complete then
        opts.on_complete(cached)
      end
      return
    end
  end

  local stop_spinner = opts.notify == false and function() end or start_spinner()
  vim.defer_fn(function()
    local ok, report = pcall(M.inspect)
    stop_spinner()
    if not ok then
      hide_spinner()
      vim.notify("Tool dependency check failed: " .. tostring(report), vim.log.levels.ERROR, {
        id = NOTIFICATION_ID,
        title = "Tool Guard",
      })
      return
    end

    local cache_ok = write_cache(key, report)
    if not cache_ok then
      report.cache_error = true
    end
    if opts.notify ~= false then
      notify_report(report, opts.quiet_if_ok)
    end
    if opts.on_complete then
      opts.on_complete(report)
    end
  end, 10)
end

function M.setup()
  vim.api.nvim_create_user_command("GuardTools", function(command)
    M.check({ force = command.bang, quiet_if_ok = false })
  end, {
    bang = true,
    desc = "Check plugin tool dependencies; use ! to bypass the cache",
  })

  vim.api.nvim_create_autocmd("User", {
    group = vim.api.nvim_create_augroup("tool_guard", { clear = true }),
    pattern = "VeryLazy",
    once = true,
    callback = function()
      vim.defer_fn(function()
        M.check({ quiet_if_ok = true })
      end, STARTUP_DELAY_MS)
    end,
  })
end

return M
