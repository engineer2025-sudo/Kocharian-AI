// Kocharian AI - HTTP server (chat, models, uploads, static UI)
import http from 'node:http';
import path from 'node:path';
import { promises as fs, createWriteStream, existsSync, mkdirSync } from 'node:fs';
import os from 'node:os';
import { pipeline } from 'node:stream/promises';
import { Readable } from 'node:stream';

import { initStore, uid, listConversations, getConversation, createConversation, saveConversation, deleteConversation, renameConversation, addMessage, listAttachments, deleteAttachment, UPLOAD_DIR } from './store.js';
import { loadSettings, saveSettings, getSettings, listModels, ensureModel, activeModelInfo, streamChat, stopGeneration, deleteModel, modelStats, resetSession, isValidGguf, MODELS_DIR, preloadModel } from './llm.js';
import { storeUploadStream, finalizeUpload, analyzeAttachment, buildAttachmentContext, categoryOf, localCapabilities, paths as toolPaths } from './attachments.js';
import { readGgufMeta } from './gguf.js';

const PORT = Number(process.env.PORT || 3000);
const HOST = process.env.HOST || '0.0.0.0';
const ROOT = path.resolve(import.meta.dirname, '..');
const PUBLIC_DIR = path.join(ROOT, 'public');
const TMP_DIR = path.join(ROOT, 'data', 'tmp');

await initStore();
mkdirSync(TMP_DIR, { recursive: true });
await loadSettings();

const json = (res, code, body) => {
  const data = Buffer.from(JSON.stringify(body));
  res.writeHead(code, { 'content-type': 'application/json; charset=utf-8', 'content-length': data.length, 'cache-control': 'no-store' });
  res.end(data);
};
const text = (res, code, body, type = 'text/plain; charset=utf-8') => {
  res.writeHead(code, { 'content-type': type, 'cache-control': 'no-store' });
  res.end(body);
};
async function readBody(req, limit = 12 * 1024 * 1024) {
  const chunks = [];
  let size = 0;
  for await (const c of req) {
    size += c.length;
    if (size > limit) throw Object.assign(new Error('body too large'), { code: 413 });
    chunks.push(c);
  }
  if (!chunks.length) return {};
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { return {}; }
}

const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8', '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.gif': 'image/gif', '.ico': 'image/x-icon', '.woff2': 'font/woff2',
  '.wav': 'audio/wav', '.mp3': 'audio/mpeg', '.m4a': 'audio/mp4', '.ogg': 'audio/ogg', '.webm': 'audio/webm',
  '.txt': 'text/plain; charset=utf-8', '.pdf': 'application/pdf', '.map': 'application/json',
  '.webmanifest': 'application/manifest+json; charset=utf-8', '.webp2': 'image/webp'
};

async function serveStatic(req, res, urlPath) {
  let rel = decodeURIComponent(urlPath.split('?')[0]);
  if (rel === '/' || rel === '') rel = '/index.html';
  const file = path.join(PUBLIC_DIR, path.normalize(rel).replace(/^([/\\])+/, ''));
  if (!file.startsWith(PUBLIC_DIR)) return text(res, 403, 'forbidden');
  try {
    const st = await fs.stat(file);
    if (!st.isFile()) throw new Error('not a file');
    res.writeHead(200, {
      'content-type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream',
      'content-length': st.size,
      'cache-control': (rel === '/index.html' || rel === '/sw.js') ? 'no-store' : 'public, max-age=300'
    });
    await pipeline((await import('node:fs')).createReadStream(file), res);
  } catch {
    // SPA fallback
    try {
      const html = await fs.readFile(path.join(PUBLIC_DIR, 'index.html'));
      res.writeHead(200, { 'content-type': MIME['.html'], 'cache-control': 'no-store' });
      res.end(html);
    } catch { text(res, 404, 'not found'); }
  }
}

/* ------------------------------------------------------------ model fetch */

const downloads = new Map();

/** python that concatenates the payload of each wheel into one file */
const CHUNK_ASSEMBLER = "import sys, zipfile, os, json\nout = sys.argv[1]\nwheels = sys.argv[2:]\nwritten = 0\nwith open(out, 'wb') as w:\n    for p in wheels:\n        z = zipfile.ZipFile(p)\n        # the payload is the largest file inside the wheel (names differ per package:\n        # part01.bin, gemma-3-270m-q4_k_m.gguf.part00, model.bin, ...)\n        names = [i for i in z.infolist() if not i.is_dir() and i.file_size > 100000]\n        if not names:\n            raise SystemExit('no payload found in ' + p)\n        entry = max(names, key=lambda i: i.file_size)\n        with z.open(entry) as f:\n            while True:\n                b = f.read(1 << 22)\n                if not b:\n                    break\n                w.write(b)\n                written += len(b)\nprint(json.dumps({\"ok\": True, \"size\": os.path.getsize(out), \"payload\": written}))\n";

const SOURCES = {
  // Hugging Face (works wherever huggingface.co is reachable, including the user's own machine)
  huggingface: ({ repo, file }) => `https://huggingface.co/${repo}/resolve/main/${file}?download=true`,
  hfmirror: ({ repo, file }) => `https://hf-mirror.com/${repo}/resolve/main/${file}?download=true`,
  modelscope: ({ repo, file }) => `https://modelscope.cn/models/${repo}/resolve/master/${file}`,
  url: ({ url }) => url
};

export const CURATED_MODELS = [
  {
    id: 'qwen1_5-1_5b-chat-q4_k_m.gguf',
    label: 'Qwen1.5-1.5B-Chat (Q4_K_M)',
    description: 'The on-board model this app ships for: 1.5B instruct Qwen, 4-bit K-quant, ~1.1 GB, needs ~1.6 GB RAM.',
    approxBytes: 1120000000,
    source: { source: 'huggingface', repo: 'Qwen/Qwen1.5-1.5B-Chat-GGUF', file: 'qwen1_5-1_5b_chat_q4_k_m.gguf' },
    mirrors: [{ source: 'hfmirror', repo: 'Qwen/Qwen1.5-1.5B-Chat-GGUF', file: 'qwen1_5-1_5b_chat_q4_k_m.gguf' }]
  },
  {
    id: 'qwen2.5-coder-1.5b-instruct-q4_k_m.gguf',
    label: 'Qwen2.5-Coder-1.5B-Instruct (Q4_K_M)',
    description: 'Preinstalled onboard model. Qwen 1.5B instruct, Q4_K_M, strong at code and instruction following.',
    approxBytes: 1117320768,
    source: { source: 'huggingface', repo: 'Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF', file: 'qwen2.5-coder-1.5b-instruct-q4_k_m.gguf' }
  },
  {
    id: 'pypi-chunks',
    label: 'Fallback: install from PyPI chunks (no Hugging Face needed)',
    description: 'Some networks block Hugging Face. This provider pulls the same GGUF from chunked PyPI packages and reassembles it locally.',
    pypiChunks: { packages: Array.from({ length: 22 }, (_, i) => `tinymentor-model-part${i + 1}`), out: 'qwen2.5-coder-1.5b-instruct-q4_k_m.gguf' }
  }
];

async function startDownload({ id, label, source, mirrors = [], targetName }) {
  const dlId = uid(8);
  const target = path.join(MODELS_DIR, path.basename(targetName || id || 'model.gguf'));
  const tmp = `${target}.part`;
  const state = { id: dlId, name: path.basename(target), status: 'starting', received: 0, total: 0, speed: 0, startedAt: Date.now(), error: null, target };
  downloads.set(dlId, state);

  (async () => {
    const candidates = [source, ...mirrors].filter(Boolean);
    let lastError = 'no source';
    for (const cand of candidates) {
      try {
        const url = SOURCES[cand.source]?.(cand);
        if (!url) { lastError = `unknown source ${cand.source}`; continue; }
        state.status = 'downloading';
        state.url = url;
        await downloadTo(url, tmp, state);
        state.status = 'verifying';
        const meta = await readGgufMeta(tmp, { budget: 8 * 1024 * 1024 });
        if (!meta?.architecture) throw new Error('downloaded file is not a valid GGUF model');
        await fs.rename(tmp, target);
        state.status = 'done';
        state.meta = meta;
        state.finishedAt = Date.now();
        return;
      } catch (err) {
        lastError = err?.message || String(err);
        state.received = 0;
        await fs.rm(tmp, { force: true }).catch(() => {});
      }
    }
    state.status = 'error';
    state.error = lastError;
  })();
  return state;
}

async function downloadTo(url, dest, state) {
  const res = await fetch(url, { redirect: 'follow' });
  if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
  state.total = Number(res.headers.get('content-length') || 0);
  const out = createWriteStream(dest);
  let last = Date.now(), lastBytes = 0;
  await pipeline(Readable.fromWeb(res.body), async function* (src) {
    for await (const chunk of src) {
      state.received += chunk.length;
      const now = Date.now();
      if (now - last > 800) { state.speed = Math.round((state.received - lastBytes) / ((now - last) / 1000)); last = now; lastBytes = state.received; }
      yield chunk;
    }
  }, out);
  state.speed = 0;
}

/* PyPI chunk provider: wheels that each contain a slice of a GGUF file. */
async function startChunkedPypiDownload(entry) {
  const dlId = uid(8);
  const target = path.join(MODELS_DIR, entry.pypiChunks.out);
  const state = { id: dlId, name: path.basename(target), status: 'starting', received: 0, total: 0, speed: 0, startedAt: Date.now(), error: null, parts: entry.pypiChunks.packages.length };
  downloads.set(dlId, state);
  (async () => {
    try {
      const work = path.join(TMP_DIR, `chunks-${dlId}`);
      await fs.mkdir(work, { recursive: true });
      const wheels = [];
      for (const pkg of entry.pypiChunks.packages) {
        state.status = `fetching ${pkg}`;
        const meta = await (await fetch(`https://pypi.org/pypi/${pkg}/json`)).json();
        const url = meta?.urls?.[0]?.url;
        if (!url) throw new Error(`no file for ${pkg}`);
        const dest = path.join(work, `${pkg}.whl`);
        await downloadTo(url, dest, state);
        wheels.push(dest);
      }
      state.status = 'assembling';
      const { execFileSync } = await import('node:child_process');
      const script = CHUNK_ASSEMBLER;
      let out = '';
      try {
        out = execFileSync('python3', ['-c', script, target, ...wheels], { maxBuffer: 1 << 24 }).toString();
      } catch (err) {
        throw new Error(`could not assemble the model parts: ${(err.stderr?.toString() || err.message || '').slice(0, 300)}`);
      }
      state.status = 'verifying';
      const meta = await readGgufMeta(target, { budget: 8 * 1024 * 1024 });
      if (!meta?.architecture) throw new Error('assembled file is not a valid GGUF');
      state.meta = meta;
      state.status = 'done';
      state.finishedAt = Date.now();
      await fs.rm(work, { recursive: true, force: true });
    } catch (err) {
      state.status = 'error';
      state.error = err?.message || String(err);
    }
  })();
  return state;
}

/* ------------------------------------------------- first-run provisioning */

/** The on-board model, installable from PyPI chunks on networks where Hugging Face is blocked. */
const ONBOARD_MODEL = {
  id: 'qwen2.5-coder-1.5b-instruct-q4_k_m.gguf',
  pypiChunks: { packages: Array.from({ length: 22 }, (_, i) => `tinymentor-model-part${i + 1}`), out: 'qwen2.5-coder-1.5b-instruct-q4_k_m.gguf' }
};

let autoProvision = null; // { id, status, received, total, ... }

async function provisionOnboardModel() {
  if (process.env.KOCHARIAN_AUTO_PROVISION === '0') return null;
  const existing = await listModels({ withMeta: false });
  if (existing.length) return null;
  console.log('\n  No on-board model found — installing the Qwen 1.5B (Q4_K_M) model in the background…');
  console.log('  (the UI shows live progress; you can also import your own .gguf at any time)');
  const state = await startChunkedPypiDownload(ONBOARD_MODEL);
  autoProvision = state;
  const tick = setInterval(async () => {
    if (['done', 'error', 'cancelled'].includes(state.status)) {
      clearInterval(tick);
      if (state.status === 'done') {
        console.log(`  on-board model ready: ${state.name} (${(state.received / 1e9).toFixed(2)} GB)`);
        await ensureModel(ONBOARD_MODEL.id).catch(() => {});
      } else {
        console.log(`  automatic model install failed: ${state.error ?? state.status}`);
        console.log('  → open the Models panel to retry, or import a GGUF file manually.');
      }
    }
  }, 3000);
  return state;
}

/* ------------------------------------------------------------------ router */

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const p = url.pathname;
  try {
    /* --- health & capabilities --- */
    if (p === '/api/health' && req.method === 'GET') {
      const models = await listModels({ withMeta: false });
      return json(res, 200, {
        ok: true, version: '1.0.0', app: 'Kocharian AI',
        model: activeModelInfo(), models: models.length,
        settings: sanitizeSettings(getSettings()),
        stats: modelStats(),
        capabilities: localCapabilities(),
        provisioning: autoProvision ? { id: autoProvision.id, status: autoProvision.status, received: autoProvision.received, total: autoProvision.total, error: autoProvision.error ?? null } : null
      });
    }
    if (p === '/api/capabilities' && req.method === 'GET') return json(res, 200, localCapabilities());

    /* --- phone / PWA helpers --- */
    if (p === '/api/network' && req.method === 'GET') {
      const nets = os.networkInterfaces();
      const lan = [];
      for (const [iface, addrs] of Object.entries(nets)) {
        for (const a of addrs ?? []) {
          if (a.family === 'IPv4' && !a.internal) lan.push({ iface, address: a.address, url: `http://${a.address}:${PORT}` });
        }
      }
      lan.sort((a, b) => (a.iface.includes('wl') ? -1 : 1) - (b.iface.includes('wl') ? -1 : 1));
      const proto = (req.headers['x-forwarded-proto'] || (req.socket.encrypted ? 'https' : 'http')).split(',')[0].trim();
      const host = (req.headers['x-forwarded-host'] || req.headers.host || `localhost:${PORT}`).split(',')[0].trim();
      return json(res, 200, {
        origin: `${proto}://${host}`,
        localhost: `http://localhost:${PORT}`,
        lan, port: PORT,
        secure: proto === 'https',
        pwa: true
      });
    }
    if (p === '/api/network/qr.svg' && req.method === 'GET') {
      const data = url.searchParams.get('data') || `http://localhost:${PORT}`;
      const size = Math.min(1024, Math.max(120, Number(url.searchParams.get('size') || 320)));
      try {
        const QRCode = (await import('qrcode')).default;
        const svg = await QRCode.toString(data, {
          type: 'svg', margin: 1, width: size, errorCorrectionLevel: 'M',
          color: { dark: '#0b0b0bff', light: '#ffffffff' }
        });
        res.writeHead(200, { 'content-type': 'image/svg+xml; charset=utf-8', 'cache-control': 'public, max-age=3600' });
        return res.end(svg);
      } catch (err) {
        return json(res, 500, { error: `QR generation failed: ${err?.message ?? err}` });
      }
    }

    /* --- settings --- */
    if (p === '/api/settings' && req.method === 'GET') return json(res, 200, sanitizeSettings(getSettings()));
    if (p === '/api/settings' && req.method === 'POST') {
      const patch = await readBody(req);
      if (patch && patch.resetAll) { const { DEFAULT_SETTINGS } = await import('./llm.js'); await saveSettings({ ...DEFAULT_SETTINGS, resetAll: undefined }); }
      else await saveSettings(patch);
      return json(res, 200, sanitizeSettings(getSettings()));
    }

    /* --- models --- */
    if (p === '/api/models' && req.method === 'GET') {
      const models = await listModels();
      return json(res, 200, { models, active: activeModelInfo()?.id ?? null, curated: CURATED_MODELS.map(({ pypiChunks, ...c }) => c), stats: modelStats() });
    }
    if (p === '/api/models/activate' && req.method === 'POST') {
      const { id } = await readBody(req);
      await ensureModel(id);
      await saveSettings({ activeModel: id });
      return json(res, 200, { ok: true, active: id, stats: modelStats() });
    }
    if (p === '/api/models/download' && req.method === 'POST') {
      const body = await readBody(req);
      let state;
      if (body.curated) {
        const entry = CURATED_MODELS.find((c) => c.id === body.curated);
        if (!entry) return json(res, 404, { error: 'unknown curated model' });
        state = entry.pypiChunks ? await startChunkedPypiDownload(entry) : await startDownload({ id: entry.id, source: entry.source, mirrors: entry.mirrors, targetName: entry.id });
      } else if (body.source) {
        state = await startDownload({ id: body.name, source: body, mirrors: body.mirrors ?? [], targetName: body.name || path.basename(body.file || body.url || 'model.gguf') });
      } else return json(res, 400, { error: 'curated or source required' });
      return json(res, 200, { id: state.id, name: state.name, status: state.status });
    }
    if (p.startsWith('/api/models/download/') && req.method === 'GET') {
      const id = p.split('/').pop();
      const state = downloads.get(id);
      if (!state) return json(res, 404, { error: 'unknown download' });
      const { target, ...safe } = state;
      return json(res, 200, safe);
    }
    if (p.startsWith('/api/models/download/') && req.method === 'DELETE') {
      const id = p.split('/').pop();
      const state = downloads.get(id);
      if (state) { state.status = 'cancelled'; downloads.delete(id); }
      return json(res, 200, { ok: true });
    }
    if (p === '/api/models/upload' && req.method === 'POST') {
      const name = path.basename(url.searchParams.get('name') || 'model.gguf');
      if (!/\.gguf$/i.test(name)) return json(res, 400, { error: 'file must end in .gguf' });
      const offset = Number(url.searchParams.get('offset') || 0);
      const done = url.searchParams.get('done') === '1';
      const target = path.join(MODELS_DIR, name);
      const tmp = `${target}.upload`;
      if (offset === 0) await fs.rm(tmp, { force: true }).catch(() => {});
      const chunks = [];
      let received = 0;
      for await (const c of req) { chunks.push(c); received += c.length; }
      await fs.appendFile(tmp, Buffer.concat(chunks));
      const size = (await fs.stat(tmp)).size;
      if (done) {
        const meta = await readGgufMeta(tmp, { budget: 8 * 1024 * 1024 });
        if (!meta?.architecture) { await fs.rm(tmp, { force: true }); return json(res, 400, { error: 'file is not a valid GGUF model' }); }
        await fs.rename(tmp, target);
        return json(res, 200, { ok: true, name, size, meta });
      }
      return json(res, 200, { ok: true, offset, received: size });
    }
    if (p === '/api/models/test' && req.method === 'POST') {
      const { id } = await readBody(req);
      const started = Date.now();
      await ensureModel(id);
      let output = '';
      let stats = null;
      try {
        for await (const evt of streamChat({
          conversationId: `__test__${id}`,
          history: [{ role: 'user', content: 'What is 2+2? Reply with the number only.' }],
          systemPrompt: 'You are a helpful assistant. Answer in as few words as possible.',
          options: { maxTokens: 24, temperature: 0.1 }
        })) {
          if (evt.type === 'done') { output = evt.text; stats = evt.stats; }
          else if (evt.type === 'error') output = `error: ${evt.message}`;
        }
      } catch (err) { output = `error: ${err?.message ?? err}`; }
      await resetSession(`__test__${id}`);
      await ensureModel(id);
      const sane = /\b4\b|four/i.test(output);
      return json(res, 200, { ok: sane, output: output.trim(), stats, elapsedMs: Date.now() - started });
    }
    if (p.startsWith('/api/models/') && req.method === 'DELETE') {
      const id = decodeURIComponent(p.replace('/api/models/', ''));
      await deleteModel(id);
      await fs.rm(path.join(MODELS_DIR, `${id}.part`), { force: true }).catch(() => {});
      return json(res, 200, { ok: true });
    }

    /* --- conversations --- */
    if (p === '/api/conversations' && req.method === 'GET') return json(res, 200, await listConversations());
    if (p === '/api/conversations' && req.method === 'POST') {
      const body = await readBody(req);
      const conv = await createConversation({ title: body.title || 'New chat', model: body.model ?? activeModelInfo()?.id ?? null, systemPrompt: body.systemPrompt ?? null });
      return json(res, 200, conv);
    }
    const convMatch = p.match(/^\/api\/conversations\/([^/]+)$/);
    if (convMatch) {
      const id = convMatch[1];
      if (req.method === 'GET') {
        const conv = await getConversation(id);
        return conv ? json(res, 200, conv) : json(res, 404, { error: 'not found' });
      }
      if (req.method === 'PATCH') {
        const body = await readBody(req);
        const conv = await renameConversation(id, body.title, body.pinned);
        return conv ? json(res, 200, conv) : json(res, 404, { error: 'not found' });
      }
      if (req.method === 'DELETE') { await deleteConversation(id); await resetSession(id); return json(res, 200, { ok: true }); }
    }
    const msgDel = p.match(/^\/api\/conversations\/([^/]+)\/messages\/(\d+)$/);
    if (msgDel && req.method === 'DELETE') {
      const conv = await getConversation(msgDel[1]);
      if (!conv) return json(res, 404, { error: 'not found' });
      conv.messages.splice(Number(msgDel[2]), 1);
      await saveConversation(conv);
      const entryReset = msgDel[1];
      await resetSession(entryReset);
      return json(res, 200, conv);
    }
    if (p === '/api/chat/stop' && req.method === 'POST') {
      const { conversationId } = await readBody(req);
      return json(res, 200, { stopped: stopGeneration(conversationId) });
    }

    /* --- chat (SSE stream) --- */
    if (p === '/api/chat' && req.method === 'POST') {
      const body = await readBody(req, 24 * 1024 * 1024);
      let conv = body.conversationId ? await getConversation(body.conversationId) : null;
      if (!conv) conv = await createConversation({ model: activeModelInfo()?.id ?? null });

      const attachmentIds = body.attachments ?? [];
      const library = await listAttachments();
      const chosen = library.filter((a) => attachmentIds.includes(a.id));
      for (const att of chosen) {
        if (!att.analysis || body.reanalyze) await analyzeAttachment(att);
      }

      const userMessage = {
        id: uid(), role: 'user', createdAt: Date.now(),
        content: String(body.content ?? '').trim() || (chosen.length ? '(no message)' : ''),
        attachments: chosen.map((a) => ({ id: a.id, name: a.name, mime: a.mime, category: a.category, size: a.size, image: a.image ?? null, audio: a.audio ?? null, analysis: a.analysis ?? null }))
      };
      await addMessage(conv, userMessage);

      const systemPrompt = conv.systemPrompt || body.systemPrompt || getSettings().systemPrompt;
      const history = [];
      for (const m of conv.messages) {
        if (m.role === 'system') continue;
        let content = m.content || '';
        const atts = (m.attachments ?? []).map((a) => ({ name: a.name, category: a.category, size: a.size, analysis: a.analysis }));
        if (atts.length) content = `${buildAttachmentContext(atts)}\n\n${content}`.trim();
        history.push({ role: m.role, content });
      }

      res.writeHead(200, {
        'content-type': 'text/event-stream; charset=utf-8',
        'cache-control': 'no-cache, no-transform',
        connection: 'keep-alive',
        'x-accel-buffering': 'no'
      });
      const send = (obj) => res.write(`data: ${JSON.stringify(obj)}\n\n`);
      send({ type: 'meta', conversationId: conv.id, userMessageId: userMessage.id, title: conv.title });
      if (!activeModelInfo()) send({ type: 'status', message: 'Loading the on-board model into memory…' });

      try {
        let full = '';
        let stats = null;
        for await (const evt of streamChat({ conversationId: conv.id, history, systemPrompt, options: body.options ?? {} })) {
          if (evt.type === 'token') { full += evt.text; send({ type: 'token', text: evt.text }); }
          else if (evt.type === 'error') send({ type: 'error', message: evt.message });
          else if (evt.type === 'done') {
            full = evt.text || full;
            stats = evt.stats ?? null;
            send({ type: 'done', text: full, stopReason: evt.stopReason, stats });
          }
        }
        const fresh = await getConversation(conv.id) ?? conv;
        const assistantMessage = { id: uid(), role: 'assistant', content: full, stats, createdAt: Date.now(), model: activeModelInfo()?.id ?? null };
        fresh.messages.push(assistantMessage);
        if (fresh.title === 'New chat' && userMessage.content) fresh.title = userMessage.content.slice(0, 48);
        await saveConversation(fresh);
        send({ type: 'saved', message: assistantMessage, title: fresh.title });
      } catch (err) {
        send({ type: 'error', message: err?.code === 'NO_MODEL' ? 'No model available. Open Models and download one.' : (err?.message ?? String(err)) });
      }
      res.end();
      return;
    }

    /* --- attachments --- */
    if (p === '/api/uploads' && req.method === 'POST') {
      const name = url.searchParams.get('name') || `file-${Date.now()}`;
      const mime = url.searchParams.get('type') || req.headers['content-type'] || 'application/octet-stream';
      const { attId, storedName, bytes } = await storeUploadStream(req, { name, mime });
      const meta = await finalizeUpload({ id: attId, name, mime, storedName, bytes });
      if (url.searchParams.get('analyze') !== '0') {
        try { await analyzeAttachment(meta); } catch (e) { meta.analysisError = String(e?.message ?? e); }
      }
      return json(res, 200, meta);
    }
    if (p === '/api/uploads' && req.method === 'GET') return json(res, 200, await listAttachments());
    if (p.startsWith('/api/uploads/') && req.method === 'DELETE') {
      const id = p.split('/').pop();
      return json(res, 200, { ok: await deleteAttachment(id) });
    }
    const analyzeMatch = p.match(/^\/api\/uploads\/([^/]+)\/analyze$/);
    if (analyzeMatch && req.method === 'POST') {
      const att = (await listAttachments()).find((a) => a.id === analyzeMatch[1]);
      if (!att) return json(res, 404, { error: 'not found' });
      const analysis = await analyzeAttachment(att);
      return json(res, 200, analysis);
    }
    const fileMatch = p.match(/^\/api\/files\/([^/]+)/);
    if (fileMatch && req.method === 'GET') {
      const att = (await listAttachments()).find((a) => a.id === fileMatch[1]);
      if (!att) return text(res, 404, 'not found');
      const file = path.join(UPLOAD_DIR, att.storedName);
      const st = await fs.stat(file).catch(() => null);
      if (!st) return text(res, 404, 'not found');
      res.writeHead(200, { 'content-type': att.mime || 'application/octet-stream', 'content-length': st.size, 'cache-control': 'public, max-age=31536000' });
      return void (await pipeline((await import('node:fs')).createReadStream(file), res));
    }

    if (p.startsWith('/api/')) return json(res, 404, { error: 'unknown endpoint' });
    return await serveStatic(req, res, p);
  } catch (err) {
    const code = err?.code === 413 ? 413 : 500;
    if (!res.headersSent) json(res, code, { error: err?.message ?? String(err) });
    else res.end();
  }
});

server.listen(PORT, HOST, () => {
  const settings = getSettings();
  console.log(`\n  Kocharian AI  •  http://localhost:${PORT}  (listening on ${HOST}:${PORT})`);
  console.log(`  models dir : ${MODELS_DIR}`);
  console.log(`  threads    : ${settings.threads} of ${os.cpus().length} CPUs  |  context: ${settings.contextSize} tokens`);
  provisionOnboardModel().then(async (state) => {
    if (!state && process.env.KOCHARIAN_NO_PRELOAD !== '1') await preloadModel();
  }).catch((err) => console.warn('  provisioning skipped:', err?.message ?? err));
});

function sanitizeSettings(s) {
  return { ...s, cloud: { ...s.cloud, apiKey: s.cloud.apiKey ? '••••' + String(s.cloud.apiKey).slice(-4) : '' } };
}
