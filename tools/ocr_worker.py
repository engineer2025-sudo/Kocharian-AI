#!/usr/bin/env python3
"""Kocharian AI - OCR worker (RapidOCR / PP-OCR, fully offline).

Usage:  python3 tools/ocr_worker.py <image-path>
Prints a single JSON line: {"ok": true, "provider": "rapidocr", "text": "...", "lines": [...], "elapsedMs": 123}
"""
import json
import os
import sys
import time

VENDOR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "vendor", "python")
if os.path.isdir(VENDOR) and VENDOR not in sys.path:
    sys.path.insert(0, VENDOR)


def main() -> int:
    if len(sys.argv) < 2:
        print(json.dumps({"ok": False, "error": "no image path given"}))
        return 2
    path = sys.argv[1]
    if not os.path.isfile(path):
        print(json.dumps({"ok": False, "error": f"file not found: {path}"}))
        return 2
    started = time.time()
    try:
        from rapidocr_onnxruntime import RapidOCR  # type: ignore
    except Exception as exc:  # pragma: no cover - dependency missing
        print(json.dumps({"ok": False, "error": f"rapidocr unavailable: {exc}"}))
        return 3
    try:
        engine = RapidOCR()
        result, elapsed = engine(path)
        lines = []
        texts = []
        if result:
            for box, text, score in result:
                xs = [p[0] for p in box]
                ys = [p[1] for p in box]
                lines.append({
                    "text": text,
                    "confidence": round(float(score), 3),
                    "box": [round(min(xs)), round(min(ys)), round(max(xs)), round(max(ys))],
                })
                texts.append(text)
        if elapsed is None:
            elapsed = [(time.time() - started) * 1000]
        print(json.dumps({
            "ok": True,
            "provider": "rapidocr",
            "text": "\n".join(texts).strip(),
            "lines": lines,
            "elapsedMs": int(sum(elapsed) if isinstance(elapsed, (list, tuple)) else elapsed),
        }))
        return 0
    except Exception as exc:  # pragma: no cover
        print(json.dumps({"ok": False, "error": f"ocr failed: {exc}"}))
        return 1


if __name__ == "__main__":
    sys.exit(main())
