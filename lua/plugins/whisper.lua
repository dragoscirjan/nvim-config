return {
  {
    "Avi-D-coder/whisper.nvim",
    config = function()
      require("whisper").setup({
        model = "base.en",
        keybind = "<C-g>",
        manual_trigger_key = "<Space>",
        debug = true, -- logs to /tmp/whisper-debug.log
      })
    end,
    keys = {
      { "<C-g>", mode = { "n", "i", "v" }, desc = "Toggle speech-to-text" },
    },
  },
}
