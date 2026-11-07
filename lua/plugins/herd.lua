return {
  {
    "akinsho/bufferline.nvim",
    opts = function(_, opts)
      opts.options = opts.options or {}
      local previous = opts.options.custom_filter
      opts.options.custom_filter = function(buf, buffers)
        if require("herd.view").is_buffer(buf) then
          return false
        end
        return not previous or previous(buf, buffers)
      end
    end,
  },
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
