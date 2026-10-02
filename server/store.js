// Kocharian AI - lightweight JSON persistence for conversations + attachments
import { mkdir, readFile, writeFile, readdir, rm } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const ROOT = path.resolve(import.meta.dirname, '..');
export const DATA_DIR = path.join(ROOT, 'data');
export const UPLOAD_DIR = path.join(DATA_DIR, 'uploads');
export const CONV_DIR = path.join(DATA_DIR, 'conversations');

export async function initStore() {
  await mkdir(CONV_DIR, { recursive: true });
  await mkdir(UPLOAD_DIR, { recursive: true });
}

export const uid = (n = 12) => crypto.randomBytes(16).toString('base64url').slice(0, n);

const convPath = (id) => path.join(CONV_DIR, `${id}.json`);

export async function listConversations() {
  const files = await readdir(CONV_DIR).catch(() => []);
  const out = [];
  for (const f of files) {
    if (!f.endsWith('.json')) continue;
    try {
      const c = JSON.parse(await readFile(path.join(CONV_DIR, f), 'utf8'));
      out.push({
        id: c.id, title: c.title, createdAt: c.createdAt, updatedAt: c.updatedAt,
        pinned: !!c.pinned, model: c.model || null,
        messageCount: (c.messages || []).length,
        preview: lastText(c)
      });
    } catch { /* ignore corrupt */ }
  }
  return out.sort((a, b) => (b.pinned - a.pinned) || (b.updatedAt - a.updatedAt));
}

function lastText(c) {
  const m = [...(c.messages || [])].reverse().find((m) => m.role === 'assistant' && m.content);
  return m ? m.content.slice(0, 140) : '';
}

export async function getConversation(id) {
  try { return JSON.parse(await readFile(convPath(id), 'utf8')); } catch { return null; }
}

export async function saveConversation(conv) {
  conv.updatedAt = Date.now();
  await writeFile(convPath(conv.id), JSON.stringify(conv, null, 2));
  return conv;
}

export async function createConversation({ title = 'New chat', model = null, systemPrompt = null } = {}) {
  const conv = { id: uid(), title, model, systemPrompt, pinned: false, createdAt: Date.now(), updatedAt: Date.now(), messages: [] };
  return saveConversation(conv);
}

export async function deleteConversation(id) {
  await rm(convPath(id), { force: true });
}

export async function renameConversation(id, title, pinned) {
  const c = await getConversation(id);
  if (!c) return null;
  if (title != null) c.title = String(title).slice(0, 120);
  if (pinned != null) c.pinned = !!pinned;
  return saveConversation(c);
}

export async function addMessage(conv, message) {
  conv.messages.push(message);
  if (conv.title === 'New chat' && message.role === 'user' && message.content) {
    conv.title = message.content.replace(/\s+/g, ' ').trim().slice(0, 48) || 'New chat';
  }
  return saveConversation(conv);
}

/* ---------- attachments library ---------- */
export async function listAttachments() {
  const idx = path.join(UPLOAD_DIR, 'index.json');
  try { return JSON.parse(await readFile(idx, 'utf8')); } catch { return []; }
}
export async function registerAttachment(meta) {
  const all = await listAttachments();
  all.unshift(meta);
  await writeFile(path.join(UPLOAD_DIR, 'index.json'), JSON.stringify(all.slice(0, 500), null, 2));
  return meta;
}
export async function deleteAttachment(id) {
  const all = await listAttachments();
  const found = all.find((a) => a.id === id);
  if (found) {
    await rm(path.join(UPLOAD_DIR, found.storedName), { force: true }).catch(() => {});
    if (found.analysis) await rm(path.join(UPLOAD_DIR, `${found.id}.analysis.json`), { force: true }).catch(() => {});
    await writeFile(path.join(UPLOAD_DIR, 'index.json'), JSON.stringify(all.filter((a) => a.id !== id), null, 2));
  }
  return !!found;
}
export const paths = { ROOT, DATA_DIR, UPLOAD_DIR, CONV_DIR };
export const exists = existsSync;
