-- whisper-stream installation:
--
-- macOS (Homebrew):
--   brew install whisper-cpp
--   Binary is at: /opt/homebrew/bin/whisper-stream (ARM) or /usr/local/bin/whisper-stream (Intel)
--   whisper.nvim auto-detects these paths — no binary_path needed on macOS.
--
-- Linux/Fedora (build from source — whisper-cpp package ships libraries only, no binary):
--   sudo dnf install -y cmake whisper-cpp-devel SDL2-devel vulkan-loader-devel glslc
--   git clone --depth=1 https://github.com/ggerganov/whisper.cpp /tmp/whisper-build
--   cmake -S /tmp/whisper-build -B /tmp/whisper-build/build -DWHISPER_SDL2=ON -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release
--   cmake --build /tmp/whisper-build/build --target whisper-stream -j$(nproc)
--   mkdir -p ~/.local/bin && cp /tmp/whisper-build/build/bin/whisper-stream ~/.local/bin/

local is_linux = vim.fn.has("linux") == 1

return {
  {
    "Avi-D-coder/whisper.nvim",
    config = function()
      local opts = {
        model = "base.en",
        keybind = "<C-g>",
        manual_trigger_key = "<Space>",
        debug = true, -- logs to /tmp/whisper-debug.log
      }

      if is_linux then
        -- Linux: binary must be built manually (see comment above)
        opts.binary_path = vim.fn.expand("~/.local/bin/whisper-stream")
        -- Lower VAD threshold — default 0.60 is too aggressive on Linux/PipeWire
        opts.vad_thold = 0.20
        -- Tune for responsiveness: step_ms = how often a chunk is transcribed
        -- length_ms = total audio context (must be >= step_ms)
        opts.step_ms = 5000
        opts.length_ms = 8000
        opts.poll_interval_ms = 5000
      end
      -- macOS: binary_path left nil → auto-detected from Homebrew paths by the plugin

      require("whisper").setup(opts)
    end,
    keys = {
      { "<C-g>", mode = { "n", "i", "v" }, desc = "Toggle speech-to-text" },
    },
  },
}
