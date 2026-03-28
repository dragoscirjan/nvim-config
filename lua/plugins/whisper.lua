-- whisper-stream installation:
--   macOS & Linux: run whisper-install.sh (builds to ~/bin/whisper.cpp/build/bin/whisper-stream)
--   NixOS: installed via system package, auto-detected from PATH

local is_linux = vim.fn.has("linux") == 1
local is_mac = vim.fn.has("mac") == 1
local is_nixos = vim.fn.filereadable("/etc/NIXOS") == 1

return {
  {
    "Avi-D-coder/whisper.nvim",
    config = function()
      local opts = {
        model = is_linux and "base.en" or "small.en",
        keybind = "<C-g>",
        manual_trigger_key = "<Space>",
        debug = true, -- logs to /tmp/whisper-debug.log
      }

      -- Timing: step_ms < length_ms gives overlapping windows for better quality;
      -- the plugin's poll_transcription_file is patched with a stabilization
      -- buffer that holds text until it stops being refined by the sliding window.
      opts.step_ms = 5000          -- transcribe every 5s
      opts.length_ms = 8000        -- 8s audio context (3s overlap between windows)
      opts.poll_interval_ms = 3000 -- check for new text every 3s

      if not is_nixos and (is_mac or is_linux) then
        -- macOS & Linux: use custom build from ~/bin/whisper.cpp (built by whisper-install.sh)
        -- NixOS: whisper-stream works well from the system package, auto-detected via PATH
        opts.binary_path = vim.fn.expand("~/bin/whisper.cpp/build/bin/whisper-stream")
      end

      if is_linux and not is_nixos then
        -- Lower VAD threshold — default 0.60 is too aggressive on Linux/PipeWire
        opts.vad_thold = 0.20
      end

      require("whisper").setup(opts)
    end,
    keys = {
      { "<C-g>", mode = { "n", "i", "v" }, desc = "Toggle speech-to-text" },
    },
  },
}
