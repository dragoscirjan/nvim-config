-- my own config

return {
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    dependencies = {
      { "github/copilot.vim" }, -- or zbirenbaum/copilot.lua
      { "nvim-lua/plenary.nvim", branch = "master" }, -- for curl, log and async functions
    },
    -- build = "make tiktoken", -- Only on MacOS or Linux
    -- @see https://github.com/neovim/neovim/issues/25019
    build = vim.fn.has("win32") == 1 and "pwsh -ExecutionPolicy Bypass -File " .. vim.fs.normalize(
      vim.fn.stdpath("config") .. "/Build-LuaTiktoken.ps1"
    ) or "make tiktoken",
    opts = {
      prompts = {
        EvaluateAndFix = {
          prompt = "Evaluate code selection and fix if you see any issues",
          selection = function(source)
            local select = require("CopilotChat.select")
            return select.visual(source)
          end,
        },
      },
    },
    keys = {
      -- { "<leader>z", name = "+copilot" },
      { "<leader>zc", ":CopilotChat<CR>", mode = { "n", "v" }, desc = "Chat with Copilot" },
      { "<leader>ze", ":CopilotChatExplain<CR>", mode = { "n", "v" }, desc = "Explain Code" },
      { "<leader>zr", ":CopilotChatReview<CR>", mode = { "n", "v" }, desc = "Review Code" },
      { "<leader>zf", ":CopilotChatFix<CR>", mode = { "n", "v" }, desc = "Fix Code" },
      { "<leader>zo", ":CopilotChatOptimize<CR>", mode = { "n", "v" }, desc = "Optimize Code" },
      { "<leader>zd", ":CopilotChatDocs<CR>", mode = { "n", "v" }, desc = "Generate Code Docs" },
      { "<leader>zt", ":CopilotChatTests<CR>", mode = { "n", "v" }, desc = "Generate Code Tests" },
      { "<leader>zm", ":CopilotChatModels<CR>", mode = { "n" }, desc = "Copilot Models" },
    },
    -- See Commands section for default commands if you want to lazy load on them
  },
}

-- return {
--   -- lua lsp
--   {
--     "neovim/nvim-lspconfig",
--     opts = {
--       servers = {
--         lua_ls = {
--           mason = false,
--         },
--       },
--     },
--   },
--   -- configure copilot
--   { "github/copilot.vim" },
-- }
