// Kocharian AI - local inference engine (llama.cpp via node-llama-cpp)
import { getLlama, LlamaChatSession, chatWrappers } from 'node-llama-cpp';
import os from 'node:os';
import path from 'node:path';
import { readdir, stat, readFile, writeFile, mkdir, rm } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { readGgufMeta } from './gguf.js';

const ROOT = path.resolve(import.meta.dirname, '..');
export const MODELS_DIR = path.join(ROOT, 'models');
const DATA_DIR = path.join(ROOT, 'data');
const SETTINGS_FILE = path.join(DATA_DIR, 'settings.json');

export const DEFAULT_SETTINGS = {
  systemPrompt:
    'You are Kocharian AI, a helpful, knowledgeable and friendly assistant running fully offline on the user\'s own computer. ' +
    'Answer clearly and concisely, use Markdown for structure and fenced code blocks for code. ' +
    'When the user attaches a file, use the extracted contents that are provided to you. ' +
    'If you are unsure about something, say so instead of inventing facts.',
  temperature: 0.7,
  topK: 40,
  topP: 0.95,
  repeatPenalty: 1.1,
  maxTokens: 512,
  contextSize: 4096,
  threads: Math.max(1, Math.min(os.cpus().length, 8)),
  gpuLayers: 'auto',
  theme: 'dark',
  chatWrapper: 'auto',       // auto | qwen | gemma | chatML | llama3 | llama3.1 | mistral | alpacaChat | general | jinjaTemplate
  asrProvider: 'auto',       // auto | local | cloud | off
  ocrProvider: 'auto',       // auto | local | cloud | off
  visionProvider: 'auto',    // auto | cloud | off
  cloud: { baseUrl: 'https://api.openai.com/v1', apiKey: '', chatModel: 'gpt-4o-mini', visionModel: 'gpt-4o-mini', asrModel: 'whisper-1' }
};

let settings = { ...DEFAULT_SETTINGS };
export const getSettings = () => settings;

export async function loadSettings() {
  try {
    const saved = JSON.parse(await readFile(SETTINGS_FILE, 'utf8'));
    settings = { ...DEFAULT_SETTINGS, ...saved, cloud: { ...DEFAULT_SETTINGS.cloud, ...(saved.cloud ?? {}) } };
  } catch { settings = { ...DEFAULT_SETTINGS }; }
  settings.threads = Math.max(1, Math.min(Number(settings.threads) || 4, os.cpus().length * 2));
  return settings;
}
export async function saveSettings(patch) {
  settings = { ...settings, ...patch, cloud: { ...settings.cloud, ...(patch.cloud ?? {}) } };
  await mkdir(DATA_DIR, { recursive: true });
  await writeFile(SETTINGS_FILE, JSON.stringify(settings, null, 2));
  return settings;
}

/* ------------------------------------------------------------------ models */

export async function listModels({ withMeta = true } = {}) {
  await mkdir(MODELS_DIR, { recursive: true });
  const entries = [];
  for (const name of await readdir(MODELS_DIR).catch(() => [])) {
    if (!name.toLowerCase().endsWith('.gguf')) continue;
    const file = path.join(MODELS_DIR, name);
    const st = await stat(file).catch(() => null);
    if (!st?.isFile()) continue;
    entries.push({ id: name, name, file, size: st.size, mtime: st.mtimeMs });
  }
  entries.sort((a, b) => b.size - a.size);
  if (withMeta) {
    await Promise.all(entries.map(async (m) => {
      m.meta = await readGgufMeta(m.file).catch(() => null);
      m.label = m.meta?.name || m.name.replace(/\.gguf$/i, '');
      m.quant = m.meta?.quantization ?? null;
      m.params = m.meta?.sizeLabel ?? null;
    }));
  }
  return entries;
}

let llamaInstance = null;
let loaded = null; // { id, model, path, meta }
const sessions = new Map(); // conversationId -> { session, ctx, sequence, lastUsed }

export async function getEngine() {
  if (!llamaInstance) {
    try { llamaInstance = await getLlama({ gpu: 'auto' }); }
    catch { llamaInstance = await getLlama({ gpu: false }); }
  }
  return llamaInstance;
}

export function activeModelInfo() {
  return loaded ? { id: loaded.id, path: loaded.path, inMemoryOnly: !existsSync(loaded.path) } : null;
}

export async function ensureModel(modelId) {
  const models = await listModels({ withMeta: false });
  // a model that is already in memory keeps working even if its file was moved or deleted
  if (!models.length) {
    if (loaded && (!modelId || modelId === loaded.id)) return loaded.model;
    const err = new Error('NO_MODEL');
    err.code = 'NO_MODEL';
    throw err;
  }
  const target = modelId ? models.find((m) => m.id === modelId || m.name === modelId) : models.find((m) => m.id === loaded?.id) ?? models[0];
  if (!target) {
    if (loaded && modelId === loaded.id) return loaded.model;
    throw Object.assign(new Error('MODEL_NOT_FOUND'), { code: 'MODEL_NOT_FOUND' });
  }
  if (loaded?.id === target.id) return loaded.model;

  await disposeEngine();
  const llama = await getEngine();
  const model = await llama.loadModel({
    modelPath: target.file,
    gpuLayers: settings.gpuLayers === 'auto' ? undefined : Number(settings.gpuLayers) || 0
  });
  const meta = await readGgufMeta(target.file, { budget: 16 * 1024 * 1024 }).catch(() => null);
  loaded = { id: target.id, model, path: target.file, loadedAt: Date.now(), meta };
  return model;
}

export async function disposeEngine() {
  for (const [id, s] of sessions) { await s.ctx?.dispose?.().catch(() => {}); sessions.delete(id); }
  if (loaded?.model) { await loaded.model.dispose().catch(() => {}); loaded = null; }
}

export async function unloadModel(modelId) {
  if (loaded?.id === modelId) await disposeEngine();
}

export function modelStats() {
  return {
    loaded: loaded ? {
      id: loaded.id, loadedAt: loaded.loadedAt, contextSize: settings.contextSize,
      architecture: loaded.meta?.architecture ?? null, quantization: loaded.meta?.quantization ?? null,
      hasChatTemplate: !!loaded.meta?.chatTemplate,
      chatTemplate: settings.chatWrapper === 'auto' ? (loaded.meta?.chatTemplate ? 'from GGUF' : 'auto-detected') : settings.chatWrapper
    } : null,
    sessions: sessions.size,
    engine: llamaInstance ? { gpu: llamaInstance.gpu, backends: llamaInstance.getBackends?.() ?? [] } : null,
    cpus: os.cpus().length,
    totalRamMB: Math.round(os.totalmem() / 1048576)
  };
}

/* ------------------------------------------------------------------ chat */

/** Pick a chat template: honour the GGUF's own template, the user's setting, or the architecture default. */
export function pickChatWrapper() {
  const requested = settings.chatWrapper || 'auto';
  const meta = loaded?.meta ?? null;
  let name = requested;
  if (requested === 'auto') {
    if (meta?.chatTemplate) return 'auto';
    const arch = String(meta?.architecture ?? '').toLowerCase();
    if (arch.startsWith('gemma')) name = 'gemma';
    else if (arch.startsWith('qwen')) name = 'qwen';
    else if (arch.startsWith('llama')) name = 'llama3';
    else name = 'general';
  }
  const Cls = chatWrappers[name];
  if (!Cls) return 'auto';
  try { return new Cls({}); } catch { return 'auto'; }
}

async function getSession(conversationId, systemPrompt) {
  let entry = sessions.get(conversationId);
  const model = await ensureModel();
  if (entry && entry.modelId === loaded.id && entry.contextSize === settings.contextSize
      && entry.systemPrompt === systemPrompt && entry.chatWrapper === settings.chatWrapper) {
    entry.lastUsed = Date.now();
    return entry;
  }
  if (entry) { await entry.ctx.dispose().catch(() => {}); sessions.delete(conversationId); }
  const ctx = await model.createContext({
    contextSize: Math.max(512, Number(settings.contextSize) || 4096),
    threads: Math.max(1, Math.min(Number(settings.threads) || 4, os.cpus().length * 2))
  });
  const sequence = ctx.getSequence();
  const chatWrapper = pickChatWrapper();
  const session = new LlamaChatSession({ contextSequence: sequence, systemPrompt, ...(chatWrapper === 'auto' ? {} : { chatWrapper }) });
  entry = { modelId: loaded.id, ctx, sequence, session, systemPrompt, contextSize: settings.contextSize, chatWrapper: settings.chatWrapper, lastUsed: Date.now() };
  sessions.set(conversationId, entry);
  // keep at most 3 warm conversations
  if (sessions.size > 3) {
    const oldest = [...sessions.entries()].sort((a, b) => a[1].lastUsed - b[1].lastUsed)[0];
    if (oldest && oldest[0] !== conversationId) {
      await oldest[1].ctx.dispose().catch(() => {});
      sessions.delete(oldest[0]);
    }
  }
  return entry;
}

export async function resetSession(conversationId) {
  const entry = sessions.get(conversationId);
  if (entry) { await entry.ctx.dispose().catch(() => {}); sessions.delete(conversationId); }
}

const controllers = new Map();

export function stopGeneration(conversationId) {
  const c = controllers.get(conversationId);
  if (c) { c.abort(); controllers.delete(conversationId); return true; }
  return false;
}

/**
 * Stream a completion. `history` is [{role, content}] (roles: user|assistant|system),
 * the last item must be the new user message.
 */
export async function* streamChat({ conversationId, history, systemPrompt, options = {}, prefillText = '' }) {
  const entry = await getSession(conversationId, systemPrompt);
  const { session, model } = { session: entry.session, model: loaded.model };

  // rebuild history so that edits / deletions are reflected (last message is prompted)
  const past = history.slice(0, -1).map((m) => m.role === 'assistant'
    ? { type: 'model', response: [m.content] }
    : { type: 'user', text: m.content });
  session.setChatHistory(past.length ? past : []);

  const last = history[history.length - 1];
  const controller = new AbortController();
  controllers.set(conversationId, controller);

  const chunks = [];
  const queue = [];
  let notify = null;
  const push = (v) => { queue.push(v); if (notify) { notify(); notify = null; } };

  const started = Date.now();
  const generation = (async () => {
    try {
      const promptText = prefillText ? `${last.content}\n\n${prefillText}` : last.content;
      const res = await session.promptWithMeta(promptText, {
        signal: controller.signal,
        stopOnAbortSignal: true,
        maxTokens: Number(options.maxTokens ?? settings.maxTokens) || 512,
        temperature: Number(options.temperature ?? settings.temperature),
        topK: Number(options.topK ?? settings.topK),
        topP: Number(options.topP ?? settings.topP),
        repeatPenalty: Number(options.repeatPenalty ?? settings.repeatPenalty),
        onTextChunk: (text) => { chunks.push(text); push({ type: 'token', text }); }
      });
      push({ type: 'done', text: res.responseText, stopReason: res.stopReason });
    } catch (err) {
      push({ type: 'error', message: err?.message ?? String(err) });
    } finally {
      controllers.delete(conversationId);
      push(null);
    }
  })();

  try {
    while (true) {
      if (!queue.length) await new Promise((r) => { notify = r; });
      const item = queue.shift();
      if (item == null) break;
      if (item.type === 'token') { yield item; continue; }
      if (item.type === 'error') { yield item; break; }
      if (item.type === 'done') {
        const elapsedMs = Date.now() - started;
        const text = item.text ?? chunks.join('');
        const completionTokens = model ? model.tokenize(text).length : 0;
        const promptTokens = model ? model.tokenize(history.map((m) => m.content).join('\n')).length : 0;
        yield {
          type: 'done', text, stopReason: item.stopReason,
          stats: { elapsedMs, completionTokens, promptTokens, tokensPerSecond: elapsedMs > 0 ? +(completionTokens / (elapsedMs / 1000)).toFixed(2) : 0 }
        };
        break;
      }
    }
  } finally {
    await generation.catch(() => {});
  }
}

/* ------------------------------------------------------------- provisioning */

export async function deleteModel(id) {
  const safe = path.basename(String(id));
  if (!safe.endsWith('.gguf')) throw new Error('bad model id');
  await unloadModel(safe);
  await rm(path.join(MODELS_DIR, safe), { force: true });
}

export function modelFile(id) { return path.join(MODELS_DIR, path.basename(String(id))); }

/** Validate a downloaded/uploaded file: it must be a readable GGUF. */
export async function isValidGguf(file) {
  const meta = await readGgufMeta(file, { budget: 8 * 1024 * 1024 });
  return !!(meta && meta.architecture);
}

/** Load the first available model into memory so the first message feels instant. */
export async function preloadModel() {
  try {
    const models = await listModels({ withMeta: false });
    if (!models.length) return null;
    const preferred = settings.activeModel && models.find((m) => m.id === settings.activeModel);
    await ensureModel((preferred ?? models[0]).id);
    return loaded?.id ?? null;
  } catch (err) {
    console.warn('[kocharian] model preload skipped:', err?.message ?? err);
    return null;
  }
}

export const dirs = { ROOT, MODELS_DIR, DATA_DIR };
export const existsSyncShim = existsSync;
