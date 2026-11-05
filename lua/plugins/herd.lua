return {
  {
    "nvim-lualine/lualine.nvim",
    init = function()
      vim.api.nvim_create_autocmd("User", {
        pattern = "VeryLazy",
        once = true,
        callback = function()
          require("herd").setup()
        end,
      })
    end,
    opts = function(_, opts)
      table.insert(opts.sections.lualine_x, {
        function()
          return require("herd").statusline()
        end,
      })
    end,
  },
}
