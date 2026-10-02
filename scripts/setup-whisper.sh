#!/usr/bin/env bash
# Kocharian AI - build whisper.cpp for on-device speech-to-text and install a Whisper model.
# Needs: git, a C++ toolchain, ~1 GB disk. Everything stays inside this repository.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v cmake >/dev/null 2>&1; then
  echo "• installing cmake (pip)"
  pip install --break-system-packages -q cmake || python3 -m pip install --break-system-packages -q cmake
fi
export PATH="$PATH:/usr/local/bin:$HOME/.local/bin"

if [ ! -d tools/whisper.cpp ]; then
  echo "• cloning whisper.cpp"
  git clone --depth 1 https://github.com/ggml-org/whisper.cpp.git tools/whisper.cpp
fi

echo "• building whisper-cli (this takes a few minutes on a laptop)"
cmake -S tools/whisper.cpp -B tools/whisper.cpp/build -DCMAKE_BUILD_TYPE=Release -DWHISPER_BUILD_TESTS=OFF >/dev/null
cmake --build tools/whisper.cpp/build -j "$(nproc 2>/dev/null || echo 2)" --config Release >/dev/null
mkdir -p tools/whisper
cp tools/whisper.cpp/build/bin/whisper-cli tools/whisper/whisper-cli
# ship the shared libraries next to the binary so the source tree can be deleted
for lib in libwhisper.so.* libggml.so.* libggml-base.so.* libggml-cpu.so.*; do
  [ -e "tools/whisper.cpp/build/bin/$lib" ] && cp -L "tools/whisper.cpp/build/bin/$lib" tools/whisper/ || true
done
echo "✓ tools/whisper/whisper-cli (+ libraries)"

mkdir -p models/whisper
if [ ! -f models/whisper/ggml-base.en.bin ] && ! ls models/whisper/*.bin >/dev/null 2>&1; then
  echo "• fetching the Whisper base.en model through npm (no Hugging Face needed)"
  tmp="$(mktemp -d)"
  (cd "$tmp" && npm pack whisper-addon@0.0.7 --silent >/dev/null && tar xzf whisper-addon-0.0.7.tgz package/models/ggml-base.en.bin \
    && mkdir -p "$ROOT/models/whisper" && cp package/models/ggml-base.en.bin "$ROOT/models/whisper/ggml-base.en.bin")
  rm -rf "$tmp"
  echo "✓ models/whisper/ggml-base.en.bin"
fi

# quantize to q5_0 (≈55 MB instead of 148 MB, same accuracy) when the tool is available
if [ -f models/whisper/ggml-base.en.bin ] && [ ! -f models/whisper/ggml-base.en-q5_0.bin ] && [ -x tools/whisper.cpp/build/bin/whisper-quantize ]; then
  echo "• quantizing the Whisper model (q5_0)"
  tools/whisper.cpp/build/bin/whisper-quantize models/whisper/ggml-base.en.bin models/whisper/ggml-base.en-q5_0.bin q5_0 >/dev/null
  rm -f models/whisper/ggml-base.en.bin
  echo "✓ models/whisper/ggml-base.en-q5_0.bin"
fi
echo "Speech-to-text is ready."
