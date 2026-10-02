#!/usr/bin/env bash
# Kocharian AI - optional high-quality OCR (PP-OCR via RapidOCR, fully offline).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
pip install --break-system-packages -q --target vendor/python rapidocr-onnxruntime onnxruntime soundfile numpy opencv-python-headless \
  || python3 -m pip install --break-system-packages -q --target vendor/python rapidocr-onnxruntime onnxruntime soundfile numpy opencv-python-headless
echo "✓ vendor/python (RapidOCR)"
if [ ! -f tools/tessdata/eng.traineddata.gz ]; then
  mkdir -p tools/tessdata
  cp node_modules/@tesseract.js-data/eng/4.0.0_best_int/eng.traineddata.gz tools/tessdata/ 2>/dev/null || true
fi
echo "OCR ready."
