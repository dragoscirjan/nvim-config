return {
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      require("herd").setup()
      table.insert(opts.sections.lualine_x, {
        function()
          return require("herd").statusline()
        end,
      })
    end,
  },
}
