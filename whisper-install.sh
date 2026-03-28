#!/usr/bin/env bash
set -euo pipefail

# Builds whisper-stream from source into ~/bin/whisper.cpp/build/bin/
# Works on both macOS and Linux. Run again to update.

INSTALL_DIR="$HOME/bin/whisper.cpp"

echo "==> Cleaning previous build..."
rm -rf "$INSTALL_DIR"
mkdir -p "$HOME/bin"

echo "==> Cloning whisper.cpp..."
git clone --depth=1 https://github.com/ggml-org/whisper.cpp "$INSTALL_DIR"

CMAKE_ARGS="-DWHISPER_SDL2=ON"

OS="$(uname -s)"
if [[ "$OS" == "Linux" ]]; then
	# Vulkan acceleration on Linux (requires vulkan-loader-devel + glslc)
	CMAKE_ARGS="$CMAKE_ARGS -DGGML_VULKAN=ON"
	echo "==> Building with SDL2 + Vulkan (Linux)..."
elif [[ "$OS" == "Darwin" ]]; then
	# Metal/Accelerate are auto-detected on macOS
	echo "==> Building with SDL2 (macOS, Metal auto-detected)..."
fi

cmake -S "$INSTALL_DIR" -B "$INSTALL_DIR/build" $CMAKE_ARGS -DCMAKE_BUILD_TYPE=Release
cmake --build "$INSTALL_DIR/build" --target whisper-stream -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu)"

BINARY="$INSTALL_DIR/build/bin/whisper-stream"
if [[ -x "$BINARY" ]]; then
	echo "==> Success! Binary at: $BINARY"
else
	echo "==> ERROR: Binary not found at $BINARY" >&2
	exit 1
fi
