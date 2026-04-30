-- Conditionally load dotnet extra when .NET project files are detected
local function is_dotnet_project()
  local patterns = { "*.csproj", "*.fsproj", "*.sln", "global.json" }
  for _, pattern in ipairs(patterns) do
    local files = vim.fn.glob(vim.fn.getcwd() .. "/" .. pattern, false, true)
    if #files > 0 then
      return true
    end
  end
  return false
end

if is_dotnet_project() then
  return {
    { import = "lazyvim.plugins.extras.lang.dotnet" },
  }
end

return {}
