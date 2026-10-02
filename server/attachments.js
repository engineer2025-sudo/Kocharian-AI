// Kocharian AI - attachment pipeline: images (OCR + metadata), audio (speech-to-text), documents (text extraction)
import path from 'node:path';
import { mkdir, writeFile, readFile, rm, stat } from 'node:fs/promises';
import fsSync from 'node:fs';
import { existsSync } from 'node:fs';
import { createWriteStream } from 'node:fs';
import { spawn, execFileSync } from 'node:child_process';
import { uid, UPLOAD_DIR, listAttachments, registerAttachment } from './store.js';
import { getSettings } from './llm.js';

const ROOT = path.resolve(import.meta.dirname, '..');
const VENDOR_PY = path.join(ROOT, 'vendor', 'python');
const WHISPER_BIN = path.join(ROOT, 'tools', 'whisper', 'whisper-cli');
const WHISPER_DIR = path.join(ROOT, 'models', 'whisper');
const OCR_WORKER = path.join(ROOT, 'tools', 'ocr_worker.py');

export function categoryOf(mime = '', name = '') {
  const m = (mime || '').toLowerCase();
  const ext = path.extname(name || '').toLowerCase();
  if (m.startsWith('image/') || ['.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp', '.avif', '.tiff'].includes(ext)) return 'image';
  if (m.startsWith('audio/') || ['.mp3', '.wav', '.m4a', '.ogg', '.oga', '.webm', '.flac', '.aac', '.opus'].includes(ext)) return 'audio';
  if (m === 'application/pdf' || ext === '.pdf') return 'pdf';
  if (m.startsWith('text/') || ['.txt', '.md', '.markdown', '.csv', '.json', '.yaml', '.yml', '.xml', '.html', '.css', '.js', '.ts', '.py', '.java', '.c', '.cpp', '.h', '.rs', '.go', '.sql', '.sh', '.log', '.ini', '.toml'].includes(ext)) return 'text';
  return 'other';
}

/* -------------------------------------------------------------- image meta */

/** Parse dimensions of the most common image formats without any dependency. */
export function imageInfo(buf) {
  try {
    if (buf.length < 24) return {};
    if (buf[0] === 0x89 && buf.toString('ascii', 1, 4) === 'PNG') {
      return { format: 'png', width: buf.readUInt32BE(16), height: buf.readUInt32BE(20) };
    }
    if (buf[0] === 0xff && buf[1] === 0xd8) {
      let p = 2;
      while (p + 9 < buf.length) {
        if (buf[p] !== 0xff) { p++; continue; }
        const marker = buf[p + 1];
        if (marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc) {
          return { format: 'jpeg', height: buf.readUInt16BE(p + 5), width: buf.readUInt16BE(p + 7) };
        }
        const len = buf.readUInt16BE(p + 2);
        p += 2 + (len || 2);
      }
      return { format: 'jpeg' };
    }
    if (buf.toString('ascii', 0, 4) === 'RIFF' && buf.toString('ascii', 8, 12) === 'WEBP') {
      const fourcc = buf.toString('ascii', 12, 16);
      if (fourcc === 'VP8X') return { format: 'webp', width: 1 + buf.readUIntLE(24, 3), height: 1 + buf.readUIntLE(27, 3) };
      if (fourcc === 'VP8 ') return { format: 'webp', width: buf.readUInt16LE(26) & 0x3fff, height: buf.readUInt16LE(28) & 0x3fff };
      if (fourcc === 'VP8L') {
        const b = buf.readUInt32LE(21);
        return { format: 'webp', width: (b & 0x3fff) + 1, height: ((b >> 14) & 0x3fff) + 1 };
      }
      return { format: 'webp' };
    }
    if (buf.toString('ascii', 0, 3) === 'GIF') return { format: 'gif', width: buf.readUInt16LE(6), height: buf.readUInt16LE(8) };
    if (buf[0] === 0x42 && buf[1] === 0x4d) return { format: 'bmp', width: buf.readInt32LE(18), height: buf.readInt32LE(22) };
  } catch { /* ignore */ }
  return {};
}

/** WAV header info (browser-recorded / converted audio is always 16k mono WAV). */
export function wavInfo(buf) {
  try {
    if (buf.toString('ascii', 0, 4) !== 'RIFF' || buf.toString('ascii', 8, 12) !== 'WAVE') return {};
    let p = 12;
    let fmt = null, dataLen = 0;
    while (p + 8 <= buf.length) {
      const id = buf.toString('ascii', p, p + 4);
      const size = buf.readUInt32LE(p + 4);
      if (id === 'fmt ') {
        fmt = { channels: buf.readUInt16LE(p + 10), sampleRate: buf.readUInt32LE(p + 12), bits: buf.readUInt16LE(p + 22) };
      } else if (id === 'data') {
        dataLen = size;
      }
      p += 8 + size + (size % 2);
    }
    const bytesPerSec = fmt ? fmt.sampleRate * fmt.channels * (fmt.bits / 8) : 0;
    return { ...(fmt ?? {}), durationSec: bytesPerSec ? +(dataLen / bytesPerSec).toFixed(2) : undefined, format: 'wav' };
  } catch { return {}; }
}

/* --------------------------------------------------------------- uploads */

export async function storeUploadStream(stream, { name, mime, id }) {
  await mkdir(UPLOAD_DIR, { recursive: true });
  const attId = id || uid(10);
  const ext = path.extname(name || '').slice(0, 12);
  const storedName = `${attId}${ext || guessExt(mime)}`;
  const file = path.join(UPLOAD_DIR, storedName);
  let bytes = 0;
  await new Promise((resolve, reject) => {
    const out = createWriteStream(file);
    stream.on('data', (c) => { bytes += c.length; });
    stream.on('error', reject);
    out.on('error', reject);
    out.on('close', resolve);
    stream.pipe(out);
  });
  return { attId, file, storedName, bytes };
}

function guessExt(mime = '') {
  const map = { 'image/png': '.png', 'image/jpeg': '.jpg', 'image/webp': '.webp', 'image/gif': '.gif', 'audio/wav': '.wav', 'audio/mpeg': '.mp3', 'audio/webm': '.webm', 'audio/ogg': '.ogg', 'audio/mp4': '.m4a', 'text/plain': '.txt', 'application/pdf': '.pdf' };
  return map[mime] || '.bin';
}

export async function finalizeUpload({ id, name, mime, storedName, bytes }) {
  const file = path.join(UPLOAD_DIR, storedName);
  const category = categoryOf(mime, name);
  const head = await readFile(file).then((b) => b.subarray(0, 512 * 1024)).catch(() => Buffer.alloc(0));
  const meta = {
    id, name: name || storedName, mime: mime || 'application/octet-stream', storedName, size: bytes,
    category, createdAt: Date.now(), analysis: null
  };
  if (category === 'image') meta.image = imageInfo(head);
  if (category === 'audio') {
    const full = await readFile(file).catch(() => head);
    meta.audio = wavInfo(full);
  }
  if (category === 'text') {
    const text = await readFile(file, 'utf8').catch(() => '');
    meta.analysis = { kind: 'text', text: text.slice(0, 20000), truncated: text.length > 20000, provider: 'direct' };
  }
  await registerAttachment(meta);
  return meta;
}

/* ------------------------------------------------------------------- OCR */

function run(cmd, args, { input, timeout = 180000, env } = {}) {
  return new Promise((resolve) => {
    const child = spawn(cmd, args, { env: { ...process.env, ...env } });
    let out = '', err = '';
    const timer = setTimeout(() => { try { child.kill('SIGKILL'); } catch {} }, timeout);
    child.stdout.on('data', (d) => { out += d; });
    child.stderr.on('data', (d) => { err += d; });
    child.on('error', (e) => { clearTimeout(timer); resolve({ code: -1, out, err: String(e.message) }); });
    child.on('close', (code) => { clearTimeout(timer); resolve({ code, out, err }); });
    if (input) { child.stdin.write(input); child.stdin.end(); } else child.stdin.end();
  });
}

/** Prefer small quantized Whisper models, then any other model in models/whisper. */
export function resolveWhisperModel() {
  if (whisperModelCache !== undefined) return whisperModelCache;
  whisperModelCache = null;
  try {
    const files = existsSync(WHISPER_DIR) ? fsSync.readdirSync(WHISPER_DIR).filter((f) => f.endsWith('.bin')) : [];
    const order = ['ggml-base.en-q5_0.bin', 'ggml-base.en-q5_1.bin', 'ggml-base.en-q8_0.bin', 'ggml-tiny.en-q5_1.bin', 'ggml-tiny.en.bin', 'ggml-small.en-q5_0.bin', 'ggml-base.en.bin', 'ggml-small.en.bin'];
    const ranked = files.sort((a, b) => {
      const ia = order.indexOf(a), ib = order.indexOf(b);
      return (ia < 0 ? 999 : ia) - (ib < 0 ? 999 : ib);
    });
    if (ranked.length) whisperModelCache = path.join(WHISPER_DIR, ranked[0]);
  } catch { /* ignore */ }
  return whisperModelCache;
}
let whisperModelCache;

export function localCapabilities() {
  const py = existsSync(path.join(VENDOR_PY, 'rapidocr_onnxruntime')) || pythonHasRapidOcr();
  return {
    ocr: { rapidocr: py, tesseractWasm: true },
    asr: { whisperCpp: existsSync(WHISPER_BIN) && !!resolveWhisperModel(), binary: WHISPER_BIN, model: resolveWhisperModel() },
    python: existsSync(VENDOR_PY)
  };
}
let pythonOcrCache = null;
function pythonHasRapidOcr() {
  if (pythonOcrCache != null) return pythonOcrCache;
  pythonOcrCache = false;
  try {
    execFileSync('python3', ['-c', 'import rapidocr_onnxruntime'], {
      stdio: 'ignore',
      env: { ...process.env, PYTHONPATH: VENDOR_PY }
    });
    pythonOcrCache = true;
  } catch { pythonOcrCache = false; }
  return pythonOcrCache;
}

export async function ocrImage(file) {
  // 1) RapidOCR (python, best quality, fully offline)
  if (existsSync(OCR_WORKER)) {
    const env = existsSync(VENDOR_PY) ? { PYTHONPATH: VENDOR_PY } : {};
    const res = await run('python3', [OCR_WORKER, file], { timeout: 240000, env });
    if (res.code === 0) {
      try {
        const data = JSON.parse(res.out.trim().split('\n').pop());
        if (data.ok) return { provider: 'rapidocr', text: data.text, lines: data.lines, elapsedMs: data.elapsedMs };
      } catch { /* fallthrough */ }
    }
  }
  // 2) tesseract.js (pure JS/WASM, offline, needs the npm packages)
  try {
    const { createWorker } = await import('tesseract.js');
    const langPath = path.join(ROOT, 'tools', 'tessdata');
    const worker = await createWorker('eng', 1, { langPath, cachePath: path.join(ROOT, 'data', 'tess-cache') });
    const t0 = Date.now();
    const { data } = await worker.recognize(file);
    await worker.terminate();
    return { provider: 'tesseract', text: (data.text || '').trim(), elapsedMs: Date.now() - t0 };
  } catch { /* not installed */ }
  return null;
}

async function cloudJson(pathname, body, { timeout = 120000 } = {}) {
  const { cloud } = getSettings();
  if (!cloud.apiKey || !cloud.baseUrl) return null;
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeout);
  try {
    const res = await fetch(`${cloud.baseUrl.replace(/\/$/, '')}${pathname}`, {
      method: 'POST', signal: ctrl.signal,
      headers: { 'content-type': 'application/json', authorization: `Bearer ${cloud.apiKey}` },
      body: JSON.stringify(body)
    });
    if (!res.ok) return null;
    return await res.json();
  } catch { return null; } finally { clearTimeout(timer); }
}

export async function cloudVision(file, prompt = 'Describe this image in detail. Extract all readable text verbatim.') {
  const { cloud } = getSettings();
  if (!cloud.apiKey) return null;
  const b64 = (await readFile(file)).toString('base64');
  const data = await cloudJson('/chat/completions', {
    model: cloud.visionModel, max_tokens: 700,
    messages: [{ role: 'user', content: [{ type: 'text', text: prompt }, { type: 'image_url', image_url: { url: `data:image/*;base64,${b64}` } }] }]
  });
  const text = data?.choices?.[0]?.message?.content;
  return text ? { provider: 'cloud-vision', text } : null;
}

/* ------------------------------------------------------------------- ASR */

export function pcm16ToWav(pcm, sampleRate = 16000, channels = 1) {
  const header = Buffer.alloc(44);
  header.write('RIFF', 0);
  header.writeUInt32LE(36 + pcm.length, 4);
  header.write('WAVE', 8);
  header.write('fmt ', 12);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20);
  header.writeUInt16LE(channels, 22);
  header.writeUInt32LE(sampleRate, 24);
  header.writeUInt32LE(sampleRate * channels * 2, 28);
  header.writeUInt16LE(channels * 2, 32);
  header.writeUInt16LE(16, 34);
  header.write('data', 36);
  header.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([header, pcm]);
}

async function convertToWav16k(srcFile, destFile) {
  // python soundfile fallback for mp3/flac/ogg uploads that were not converted in the browser
  const script = `
import sys, json
try:
    import soundfile as sf, numpy as np
except Exception as e:
    print(json.dumps({"ok": False, "err": str(e)})); sys.exit(0)
try:
    data, sr = sf.read(sys.argv[1])
    if data.ndim > 1: data = data.mean(axis=1)
    if sr != 16000:
        n = int(len(data) * 16000 / sr)
        data = np.interp(np.linspace(0, len(data) - 1, n), np.arange(len(data)), data)
        sr = 16000
    import wave, struct
    pcm = (np.clip(data, -1, 1) * 32767).astype('<i2').tobytes()
    w = wave.open(sys.argv[2], 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr); w.writeframes(pcm); w.close()
    print(json.dumps({"ok": True, "duration": len(data)/sr}))
except Exception as e:
    print(json.dumps({"ok": False, "err": str(e)}))
`;
  const env = existsSync(VENDOR_PY) ? { PYTHONPATH: VENDOR_PY } : {};
  const res = await run('python3', ['-c', script, srcFile, destFile], { timeout: 180000, env });
  try { return JSON.parse(res.out.trim().split('\n').pop()); } catch { return { ok: false, err: res.err || 'conversion failed' }; }
}

export async function transcribeAudio(file, { language = 'en', model = 'base.en' } = {}) {
  if (!existsSync(file)) return null;
  let wav = file;
  const buf = await readFile(file).catch(() => null);
  if (!buf) return null;
  const isWav = buf.toString('ascii', 0, 4) === 'RIFF' && buf.toString('ascii', 8, 12) === 'WAVE';
  let tmpWav = null;
  if (!isWav) {
    tmpWav = `${file}.16k.wav`;
    const conv = await convertToWav16k(file, tmpWav);
    if (!conv.ok) return { provider: 'none', error: `Unsupported audio format (${conv.err || 'no converter available'}). Try WAV/MP3.` };
    wav = tmpWav;
  }
  try {
    const whisperModel = resolveWhisperModel();
    if (existsSync(WHISPER_BIN) && whisperModel) {
      const outBase = `${file}.out`;
      const cpus = (await import('node:os')).cpus().length;
      const res = await run(WHISPER_BIN, [
        '-m', whisperModel, '-f', wav, '-l', language === 'auto' ? 'auto' : language,
        '-otxt', '-of', outBase, '-nt', '--no-prints', '-t', String(Math.max(1, Math.min(4, cpus)))
      ], { timeout: 900000, env: { LD_LIBRARY_PATH: path.dirname(WHISPER_BIN) + (process.env.LD_LIBRARY_PATH ? `:${process.env.LD_LIBRARY_PATH}` : '') } });
      const txt = await readFile(`${outBase}.txt`, 'utf8').catch(() => null);
      await rm(`${outBase}.txt`, { force: true }).catch(() => {});
      if (txt != null) return { provider: 'whisper.cpp', model: path.basename(whisperModel), text: txt.trim(), logs: res.code === 0 ? undefined : res.err.slice(-400) };
    }
    const cloud = await transcribeCloud(file);
    if (cloud) return cloud;
    return { provider: 'none', error: 'No local speech-to-text engine available. Build whisper.cpp (npm run setup:whisper) or add a cloud API key in Settings.' };
  } finally {
    if (tmpWav) await rm(tmpWav, { force: true }).catch(() => {});
  }
}

export async function transcribeCloud(file) {
  const { cloud } = getSettings();
  if (!cloud.apiKey) return null;
  const buf = await readFile(file);
  const fd = new FormData();
  fd.append('file', new Blob([buf]), path.basename(file));
  fd.append('model', cloud.asrModel || 'whisper-1');
  try {
    const res = await fetch(`${cloud.baseUrl.replace(/\/$/, '')}/audio/transcriptions`, { method: 'POST', headers: { authorization: `Bearer ${cloud.apiKey}` }, body: fd });
    if (!res.ok) return null;
    const data = await res.json();
    return data.text ? { provider: 'cloud-asr', text: data.text } : null;
  } catch { return null; }
}

/* --------------------------------------------------------------- analysis */

export async function analyzeAttachment(att) {
  const file = path.join(UPLOAD_DIR, att.storedName);
  const { asrProvider, ocrProvider, visionProvider, cloud } = getSettings();
  let analysis = att.analysis ?? null;

  if (att.category === 'image') {
    analysis = { kind: 'image', image: att.image, provider: 'metadata' };
    if (ocrProvider !== 'off') {
      const ocr = ocrProvider === 'cloud' ? null : await ocrImage(file);
      if (ocr) analysis.ocr = ocr;
      else if (ocrProvider !== 'local' && cloud.apiKey) {
        const cv = await cloudVision(file, 'Extract all readable text from this image verbatim. Then briefly describe the image.');
        if (cv) analysis.vision = cv;
      }
      if (!analysis.ocr && !analysis.vision && visionProvider === 'cloud' && cloud.apiKey && ocrProvider !== 'local') {
        const cv = await cloudVision(file);
        if (cv) analysis.vision = cv;
      }
    }
    if (!analysis.ocr && !analysis.vision && (visionProvider === 'cloud' || visionProvider === 'auto') && cloud.apiKey) {
      const cv = await cloudVision(file);
      if (cv) analysis.vision = cv;
    }
  } else if (att.category === 'audio') {
    analysis = { kind: 'audio', audio: att.audio, provider: 'metadata' };
    if (asrProvider !== 'off') {
      const local = asrProvider === 'cloud' ? null : await transcribeAudio(file);
      if (local && local.text != null) analysis.asr = local;
      else if (asrProvider !== 'local') {
        const cl = await transcribeCloud(file);
        if (cl) analysis.asr = cl; else analysis.asr = local ?? { provider: 'none' };
      } else analysis.asr = local;
    }
  } else if (att.category === 'pdf') {
    analysis = { kind: 'pdf', provider: 'none', error: 'PDF text extraction needs the optional pdfjs-dist package.' };
    try {
      const pdfjs = await import('pdfjs-dist/legacy/build/pdf.mjs');
      const data = new Uint8Array(await readFile(file));
      const doc = await pdfjs.getDocument({ data, useSystemFonts: true }).promise;
      const pages = [];
      for (let i = 1; i <= Math.min(doc.numPages, 30); i++) {
        const page = await doc.getPage(i);
        const content = await page.getTextContent();
        pages.push(content.items.map((it) => it.str).join(' '));
      }
      analysis = { kind: 'pdf', provider: 'pdfjs', pages: doc.numPages, text: pages.join('\n\n').slice(0, 30000) };
    } catch { /* optional */ }
  } else if (att.category === 'text') {
    const text = await readFile(file, 'utf8').catch(() => '');
    analysis = { kind: 'text', provider: 'direct', text: text.slice(0, 30000), truncated: text.length > 30000 };
  } else {
    analysis = { kind: 'other', provider: 'none' };
  }

  att.analysis = analysis;
  await writeFile(path.join(UPLOAD_DIR, `${att.id}.analysis.json`), JSON.stringify(analysis, null, 2)).catch(() => {});
  const all = await listAttachments();
  const idx = all.findIndex((a) => a.id === att.id);
  if (idx >= 0) { all[idx] = { ...all[idx], analysis }; await registerAttachmentMany(all); }
  return analysis;
}

async function registerAttachmentMany(all) {
  await writeFile(path.join(UPLOAD_DIR, 'index.json'), JSON.stringify(all.slice(0, 500), null, 2));
}

/** Build the text block that is injected into the prompt for attached files. */
export function buildAttachmentContext(items) {
  if (!items?.length) return '';
  const blocks = [];
  for (const it of items) {
    const a = it.analysis ?? {};
    const head = `### Attachment: ${it.name} (${it.category}${it.size ? `, ${(it.size / 1024).toFixed(0)} KB` : ''})`;
    const parts = [];
    if (a.image?.width) parts.push(`Dimensions: ${a.image.width}x${a.image.height}px`);
    if (a.audio) {
      const bits = [];
      if (a.audio.durationSec) bits.push(`${a.audio.durationSec}s`);
      if (a.audio.sampleRate) bits.push(`${a.audio.sampleRate} Hz`);
      if (bits.length) parts.push(`Audio: ${bits.join(', ')}`);
    }
    if (a.ocr?.text) parts.push(`Text recognised in the image (OCR, ${a.ocr.provider}):\n"""\n${a.ocr.text.slice(0, 8000)}\n"""`);
    if (a.vision?.text) parts.push(`Image description (vision model):\n"""\n${a.vision.text.slice(0, 8000)}\n"""`);
    if (a.asr?.text) parts.push(`Speech transcript (${a.asr.provider}):\n"""\n${a.asr.text.slice(0, 8000)}\n"""`);
    if (a.asr?.error) parts.push(`Speech-to-text could not run: ${a.asr.error}`);
    if (a.text) parts.push(`File contents:\n"""\n${a.text.slice(0, 12000)}\n"""`);
    if (!parts.length) parts.push('(no automatic content could be extracted from this attachment)');
    blocks.push(`${head}\n${parts.join('\n')}`);
  }
  return `The user attached ${items.length} file${items.length > 1 ? 's' : ''}. Extracted content:\n\n${blocks.join('\n\n')}`;
}

export async function deleteAnalysis(id) {
  await rm(path.join(UPLOAD_DIR, `${id}.analysis.json`), { force: true }).catch(() => {});
}

export const paths = { VENDOR_PY, WHISPER_BIN, WHISPER_DIR, OCR_WORKER };
export { stat };
