-- Enable Neovim's experimental messages and command-line UI when available.
local has_ui2, ui2 = pcall(require, "vim._core.ui2")
if has_ui2 then
  ui2.enable()
end

require("config.guard").setup()

-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
