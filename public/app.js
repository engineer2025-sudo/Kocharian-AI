/* Kocharian AI — front-end app (vanilla ES modules, no build step) */

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
const el = (tag, props = {}, ...kids) => {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (k === 'class') n.className = v;
    else if (k === 'html') n.innerHTML = v;
    else if (k === 'text') n.textContent = v;
    else if (k.startsWith('on')) n.addEventListener(k.slice(2), v);
    else if (v != null) n.setAttribute(k, v);
  }
  for (const kid of kids.flat()) if (kid != null) n.append(kid);
  return n;
};
const CATEGORY_ICON = {
  image: '<svg viewBox="0 0 24 24" class="ic"><rect x="3" y="4" width="18" height="16" rx="2.5"/><circle cx="9" cy="10" r="1.7"/><path d="M4 18l5-5 3.5 3.5L16 13l4 4"/></svg>',
  audio: '<svg viewBox="0 0 24 24" class="ic"><path d="M9 18V7l10-2v11"/><circle cx="6.5" cy="18" r="2.6"/><circle cx="16.5" cy="16" r="2.6"/></svg>',
  pdf: '<svg viewBox="0 0 24 24" class="ic"><path d="M6 3h8l4 4v14H6z"/><path d="M14 3v4h4"/><path d="M9 13h6M9 16.5h4"/></svg>',
  text: '<svg viewBox="0 0 24 24" class="ic"><path d="M6 3h8l4 4v14H6z"/><path d="M14 3v4h4"/><path d="M9 12h6M9 15.5h6"/></svg>',
  other: '<svg viewBox="0 0 24 24" class="ic"><path d="M4 5h6l2 2h8v12H4z"/></svg>'
};
const fmtBytes = (b) => b > 1e9 ? (b / 1e9).toFixed(2) + ' GB' : b > 1e6 ? (b / 1e6).toFixed(1) + ' MB' : b > 1e3 ? (b / 1e3).toFixed(0) + ' KB' : b + ' B';
const fmtTime = (t) => new Date(t).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
const relTime = (t) => {
  const d = Date.now() - t;
  if (d < 60000) return 'now';
  if (d < 3600000) return Math.floor(d / 60000) + 'm';
  if (d < 86400000) return Math.floor(d / 3600000) + 'h';
  if (d < 7 * 86400000) return Math.floor(d / 86400000) + 'd';
  return new Date(t).toLocaleDateString();
};

const state = {
  conversations: [], current: null, streaming: false, attachments: [], settings: {},
  models: [], curated: [], health: null, controller: null, filter: '', recording: null
};

/* ---------------------------------------------------------------- markdown */

const escapeHtml = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

function inlineMd(s) {
  let t = escapeHtml(s);
  t = t.replace(/`([^`]+)`/g, (_, c) => `<code>${c}</code>`);
  t = t.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  t = t.replace(/(^|\W)\*([^*\n]+)\*(?=\W|$)/g, '$1<em>$2</em>');
  t = t.replace(/~~([^~]+)~~/g, '<del>$1</del>');
  t = t.replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g, '<a href="$1" target="_blank" rel="noreferrer">$2</a>');
  t = t.replace(/(^|\s)(https?:\/\/[^\s<]+)/g, '$1<a href="$2" target="_blank" rel="noreferrer">$2</a>');
  return t;
}

function mdBlocks(src) {
  const lines = String(src).replace(/\r\n?/g, '\n').split('\n');
  const out = [];
  let i = 0;
  const isTableSep = (l) => /^\s*\|?[\s:-]+\|[\s:|-]*$/.test(l);
  while (i < lines.length) {
    const line = lines[i];
    // fenced code
    const fence = line.match(/^\s*```(\S*)\s*$/);
    if (fence) {
      const lang = fence[1] || '';
      const buf = [];
      i++;
      while (i < lines.length && !/^\s*```\s*$/.test(lines[i])) buf.push(lines[i++]);
      i++;
      out.push({ type: 'code', lang, code: buf.join('\n') });
      continue;
    }
    if (/^\s*$/.test(line)) { i++; continue; }
    const h = line.match(/^(#{1,6})\s+(.*)$/);
    if (h) { out.push({ type: 'html', html: `<h${h[1].length}>${inlineMd(h[2])}</h${h[1].length}>` }); i++; continue; }
    if (/^\s*([-*_])\s*\1\s*\1[\s-*_]*$/.test(line)) { out.push({ type: 'html', html: '<hr/>' }); i++; continue; }
    if (/^\s*>\s?/.test(line)) {
      const buf = [];
      while (i < lines.length && /^\s*>\s?/.test(lines[i])) buf.push(lines[i++].replace(/^\s*>\s?/, ''));
      out.push({ type: 'html', html: `<blockquote>${mdBlocks(buf.join('\n')).map(renderBlock).join('')}</blockquote>` });
      continue;
    }
    if (/^\s*\|.*\|\s*$/.test(line) && i + 1 < lines.length && isTableSep(lines[i + 1])) {
      const cells = (l) => l.trim().replace(/^\||\|$/g, '').split('|').map((c) => c.trim());
      const head = cells(line);
      i += 2;
      const rows = [];
      while (i < lines.length && /^\s*\|.*\|\s*$/.test(lines[i])) rows.push(cells(lines[i++]));
      out.push({ type: 'html', html: `<table><thead><tr>${head.map((c) => `<th>${inlineMd(c)}</th>`).join('')}</tr></thead><tbody>${rows.map((r) => `<tr>${r.map((c) => `<td>${inlineMd(c)}</td>`).join('')}</tr>`).join('')}</tbody></table>` });
      continue;
    }
    if (/^\s*([-*+]|\d+[.)])\s+/.test(line)) {
      const ordered = /^\s*\d+[.)]\s+/.test(line);
      const items = [];
      while (i < lines.length && /^\s*([-*+]|\d+[.)])\s+/.test(lines[i])) {
        items.push(lines[i++].replace(/^\s*([-*+]|\d+[.)])\s+/, ''));
      }
      const tag = ordered ? 'ol' : 'ul';
      out.push({ type: 'html', html: `<${tag}>${items.map((it) => `<li>${inlineMd(it)}</li>`).join('')}</${tag}>` });
      continue;
    }
    const buf = [line];
    i++;
    while (i < lines.length && !/^\s*$/.test(lines[i]) && !/^\s*(```|#{1,6}\s|>|[-*+]\s|\d+[.)]\s|\|)/.test(lines[i])) buf.push(lines[i++]);
    out.push({ type: 'html', html: `<p>${inlineMd(buf.join('\n')).replace(/\n/g, '<br/>')}</p>` });
  }
  return out;
}

const HL_RULES = [
  ['c', /\/\/[^\n]*|#[^\n]*|\/\*[\s\S]*?\*\//],
  ['s', /"""[\s\S]*?"""|"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'|`(?:[^`\\]|\\.)*`/],
  ['n', /\b\d+(?:\.\d+)?\b/],
  ['k', /\b(?:const|let|var|function|return|if|else|for|while|import|from|export|class|new|await|async|try|catch|finally|throw|def|elif|lambda|pass|raise|with|as|in|not|and|or|None|True|False|self|public|private|static|void|int|float|double|String|bool|struct|enum|interface|extends|implements|package|fn|impl|match|use|pub|mut|echo|then|fi|do|done|type|let)\b/],
  ['f', /\b[A-Za-z_]\w*(?=\s*\()/]
];
const HL_RE = new RegExp(HL_RULES.map(([, r]) => `(${r.source})`).join('|'), 'g');

/** Single-pass syntax highlighting — emitted markup is never re-processed. */
function highlight(code) {
  HL_RE.lastIndex = 0;
  let out = '', last = 0, m;
  while ((m = HL_RE.exec(code))) {
    if (m[0].length === 0) { HL_RE.lastIndex++; continue; }
    out += escapeHtml(code.slice(last, m.index));
    const idx = m.slice(1).findIndex((g) => g !== undefined);
    const cls = HL_RULES[idx < 0 ? 0 : idx][0];
    out += `<span class="${cls}">${escapeHtml(m[0])}</span>`;
    last = m.index + m[0].length;
  }
  return out + escapeHtml(code.slice(last));
}

function renderBlock(b) {
  if (b.type === 'html') return b.html;
  if (b.type === 'code') {
    return `<pre><div class="pre-head"><span>${escapeHtml(b.lang || 'code')}</span><button class="copy-btn" data-copy>Copy</button></div><code>${highlight(b.code)}</code></pre>`;
  }
  return '';
}


function renderMarkdown(src) {
  return mdBlocks(src).map(renderBlock).join('');
}

/* -------------------------------------------------------------- api helper */

async function api(path, { method = 'GET', body, raw, headers = {} } = {}) {
  const res = await fetch(path, {
    method,
    headers: body && !raw ? { 'content-type': 'application/json', ...headers } : headers,
    body: raw ? body : body ? JSON.stringify(body) : undefined
  });
  const ct = res.headers.get('content-type') || '';
  const data = ct.includes('application/json') ? await res.json().catch(() => null) : await res.text();
  if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
  return data;
}

function toast(message, kind = '') {
  const t = el('div', { class: `toast ${kind}`, text: message });
  $('#toasts').append(t);
  setTimeout(() => t.remove(), kind === 'err' ? 8000 : 4000);
}

/* -------------------------------------------------------------- sidebar UI */

async function loadConversations() {
  state.conversations = await api('/api/conversations').catch(() => []);
  renderConversations();
}

function renderConversations() {
  const list = $('#convList');
  list.innerHTML = '';
  const q = state.filter.toLowerCase();
  const items = state.conversations.filter((c) => !q || (c.title || '').toLowerCase().includes(q) || (c.preview || '').toLowerCase().includes(q));
  if (!items.length) {
    list.append(el('div', { class: 'muted small', style: 'padding:10px', text: q ? 'No chats match.' : 'No chats yet — start one!' }));
    return;
  }
  for (const c of items) {
    const node = el('div', { class: `conv-item ${state.current?.id === c.id ? 'active' : ''}`, title: c.preview || c.title },
      el('span', { class: 't', text: (c.pinned ? '★ ' : '') + (c.title || 'New chat') }),
      el('span', { class: 'when', text: relTime(c.updatedAt) }),
      el('span', { class: 'row-actions' },
        el('button', { class: 'mini', title: 'Rename', html: '✏️', onclick: async (e) => { e.stopPropagation(); const t = prompt('Chat name', c.title); if (t) { await api(`/api/conversations/${c.id}`, { method: 'PATCH', body: { title: t } }); await loadConversations(); if (state.current?.id === c.id) $('#chatTitle').textContent = t; } } }),
        el('button', { class: 'mini', title: c.pinned ? 'Unpin' : 'Pin', html: '📌', onclick: async (e) => { e.stopPropagation(); await api(`/api/conversations/${c.id}`, { method: 'PATCH', body: { pinned: !c.pinned } }); await loadConversations(); } }),
        el('button', { class: 'mini', title: 'Delete', html: '🗑️', onclick: async (e) => { e.stopPropagation(); if (confirm(`Delete "${c.title}"?`)) { await api(`/api/conversations/${c.id}`, { method: 'DELETE' }); if (state.current?.id === c.id) { state.current = null; renderChat(); } await loadConversations(); } } })
      ),
      el('span', { style: 'display:none' })
    );
    node.addEventListener('click', () => openConversation(c.id));
    list.append(node);
  }
}

async function newChat() {
  state.current = await api('/api/conversations', { method: 'POST', body: {} });
  state.attachments = [];
  await loadConversations();
  renderChat();
  $('#input').focus();
}

async function openConversation(id) {
  state.current = await api(`/api/conversations/${id}`).catch(() => null);
  state.attachments = [];
  closeSidebar();
  renderChat();
  renderConversations();
}

function closeSidebar() { $('#sidebar').classList.remove('open'); $('#scrim').classList.remove('show'); }

/* -------------------------------------------------------------- chat view */

function emptyState() {
  const cards = [
    { t: 'Explain something', s: '“Explain how HTTPS works, simply.”', p: 'Explain how HTTPS works in simple terms, with an analogy.' },
    { t: 'Write code', s: '“A Python script that renames photos by date.”', p: 'Write a Python script that renames all photos in a folder by their EXIF date.' },
    { t: 'Read an image', s: 'Attach a screenshot — text is extracted locally with OCR.', p: '' },
    { t: 'Transcribe audio', s: 'Attach or record audio — it is transcribed on-device.', p: '' }
  ];
  const wrap = el('div', { class: 'empty' },
    el('div', { class: 'logo', text: 'K' }),
    el('h1', { text: 'How can I help today?' }),
    el('p', { html: 'Running <b>fully on this machine</b> — your chats, images and audio never leave it.' }),
    el('div', { class: 'cards' }, cards.map((c) => el('div', { class: 'card', onclick: () => { if (c.p) { $('#input').value = c.p; autoGrow(); $('#input').focus(); } else $('#attachBtn').click(); } }, el('b', { text: c.t }), el('span', { text: c.s })))),
    el('div', { class: 'meta-row', id: 'emptyMeta' })
  );
  return wrap;
}

function attachmentChip(a, { interactive = true } = {}) {
  const icon = CATEGORY_ICON[a.category] ?? CATEGORY_ICON.other;
  const tag = a.analysis?.ocr?.text ? 'OCR done' : a.analysis?.asr?.text ? 'Transcribed' : a.analysis?.asr?.error ? 'No STT' : a.category;
  const node = el('div', { class: 'chip', title: a.name },
    a.category === 'image' && a.id ? el('img', { src: `/api/files/${a.id}`, alt: '' }) : el('span', { class: 'file-glyph', html: icon }),
    el('div', {}, el('div', { text: a.name }), el('div', { class: 'tag', text: tag }))
  );
  if (interactive) node.addEventListener('click', () => openViewer(a));
  return node;
}

function renderChat() {
  const box = $('#messages');
  box.innerHTML = '';
  $('#chatTitle').textContent = state.current?.title || 'New chat';
  if (!state.current || !state.current.messages?.length) {
    box.append(emptyState());
    updateEmptyMeta();
    return;
  }
  const msgs = state.current.messages;
  msgs.forEach((m, idx) => box.append(renderMessage(m, idx)));
  scrollToBottom(true);
}

function updateEmptyMeta() {
  const meta = $('#emptyMeta');
  if (!meta || !state.health) return;
  const caps = state.health.capabilities ?? {};
  const prov = state.health.provisioning;
  meta.innerHTML = '';
  if (prov && !['done', 'error', 'cancelled'].includes(prov.status)) {
    const pct = prov.total ? Math.min(100, (prov.received / prov.total) * 100).toFixed(0) + '%' : fmtBytes(prov.received);
    meta.append(el('span', { html: `installing the on-board model: <code>${pct}</code> (${prov.status})` }));
  }
  meta.append(
    el('span', { html: `model: <code>${state.health.model?.id ?? 'none'}</code>` }),
    el('span', { html: `text-from-images: <code>${caps.ocr ? 'on' : 'off'}</code>` }),
    el('span', { html: `speech-to-text: <code>${caps.asr?.whisperCpp ? 'on' : 'off'}</code>` }),
    el('span', { html: `threads: <code>${state.health.settings?.threads ?? '?'}</code>` })
  );
}

function renderMessage(m, idx) {
  const isUser = m.role === 'user';
  const body = el('div', { class: 'body' });
  const name = isUser ? 'You' : 'Kocharian AI';
  body.append(el('div', { class: 'who', text: `${name} · ${fmtTime(m.createdAt || Date.now())}` }));

  const atts = m.attachments ?? [];
  for (const a of atts) {
    if (a.category === 'image' && a.id) {
      body.append(el('img', { class: 'attach-thumb', src: `/api/files/${a.id}`, alt: a.name, onclick: () => openViewer(a) }));
    } else if (a.category === 'audio' && a.id) {
      body.append(el('audio', { controls: '', src: `/api/files/${a.id}` }));
      if (a.analysis?.asr?.text) body.append(el('div', { class: 'msg-stats', text: `Transcript: “${a.analysis.asr.text.slice(0, 180)}${a.analysis.asr.text.length > 180 ? '…' : ''}”` }));
      else if (a.analysis?.asr?.error) body.append(el('div', { class: 'msg-stats', text: `⚠️ ${a.analysis.asr.error}` }));
    }
  }
  if (atts.length) {
    body.append(el('div', { class: 'chips' }, atts.map((a) => attachmentChip(a))));
  }

  const content = el('div', { class: 'content' });
  if (isUser) content.textContent = m.content;
  else content.innerHTML = renderMarkdown(m.content || '');
  body.append(content);

  if (!isUser && m.stats) {
    body.append(el('div', { class: 'msg-stats', text: `${m.stats.completionTokens ?? '?'} tokens · ${(m.stats.elapsedMs / 1000).toFixed(1)}s · ${m.stats.tokensPerSecond ?? '?'} tok/s` }));
  }

  const actions = el('div', { class: 'msg-actions' });
  actions.append(el('button', { class: 'mini-act', text: 'Copy', onclick: () => { navigator.clipboard.writeText(m.content || ''); toast('Copied'); } }));
  if (isUser) {
    actions.append(el('button', { class: 'mini-act', text: 'Edit', onclick: () => editMessage(idx, m) }));
  } else {
    actions.append(el('button', { class: 'mini-act', text: 'Regenerate', onclick: () => regenerate(idx) }));
  }
  actions.append(el('button', { class: 'mini-act', text: 'Delete', onclick: async () => { await api(`/api/conversations/${state.current.id}/messages/${idx}`, { method: 'DELETE' }); state.current = await api(`/api/conversations/${state.current.id}`); renderChat(); await loadConversations(); } }));
  body.append(actions);

  return el('div', { class: `msg ${isUser ? 'user' : 'assistant'}` },
    el('div', { class: 'avatar', html: isUser ? '<svg viewBox="0 0 24 24" class="ic" style="width:17px;height:17px"><circle cx="12" cy="8.4" r="3.5"/><path d="M5.2 19.6c1.2-3.5 3.9-5.2 6.8-5.2s5.6 1.7 6.8 5.2"/></svg>' : 'K' }),
    body
  );
}

function editMessage(idx, m) {
  const node = $$('#messages .msg')[idx];
  const content = $('.content', node);
  const original = m.content;
  content.innerHTML = '';
  const ta = el('textarea', { rows: 3, style: 'width:100%;min-width:280px' });
  ta.value = original;
  content.append(ta, el('div', { class: 'row', style: 'margin-top:6px' },
    el('button', { class: 'btn small', text: 'Send', onclick: async () => {
      const text = ta.value.trim();
      await api(`/api/conversations/${state.current.id}/messages/${idx}`, { method: 'DELETE' });
      state.current = await api(`/api/conversations/${state.current.id}`);
      renderChat();
      send(text);
    } }),
    el('button', { class: 'btn small ghost', text: 'Cancel', onclick: () => renderChat() })
  ));
  ta.focus();
}

async function regenerate(idx) {
  const msgs = state.current.messages;
  let userMsg = null;
  for (let i = idx - 1; i >= 0; i--) if (msgs[i].role === 'user') { userMsg = msgs[i]; break; }
  if (!userMsg) return;
  await api(`/api/conversations/${state.current.id}/messages/${idx}`, { method: 'DELETE' });
  state.current = await api(`/api/conversations/${state.current.id}`);
  renderChat();
  send(userMsg.content, { skipUserMessage: true, attachments: (userMsg.attachments ?? []).map((a) => a.id) });
}

/* ------------------------------------------------------------- streaming */

async function send(textOverride, opts = {}) {
  if (state.streaming) return;
  const input = $('#input');
  const text = (textOverride ?? input.value).trim();
  const attachments = opts.attachments ?? state.attachments.map((a) => a.id);
  if (!text && !attachments.length) return;
  if (!state.current) state.current = await api('/api/conversations', { method: 'POST', body: {} }).catch(() => null);
  if (!state.current) return toast('Could not create the chat', 'err');

  if (!opts.skipUserMessage) {
    const userMsg = {
      id: 'tmp-' + Date.now(), role: 'user', content: text || '(no message)', createdAt: Date.now(),
      attachments: state.attachments.map((a) => ({ id: a.id, name: a.name, category: a.category, size: a.size, image: a.image, audio: a.audio, analysis: a.analysis }))
    };
    state.current.messages = [...(state.current.messages ?? []), userMsg];
    if (state.current.messages.length === 1) state.current.title = (text || 'New chat').slice(0, 48);
    input.value = '';
    autoGrow();
    state.attachments = [];
    renderAttachStrip();
    renderChat();
  }

  const assistantNode = el('div', { class: 'msg assistant' },
    el('div', { class: 'avatar', text: 'K' }),
    el('div', { class: 'body' },
      el('div', { class: 'who', text: `Kocharian AI · ${fmtTime(Date.now())}` }),
      el('div', { class: 'content cursor' }),
      el('div', { class: 'msg-stats', text: 'thinking…' })
    )
  );
  const box = $('#messages');
  if (box.querySelector('.empty')) box.innerHTML = '';
  box.append(assistantNode);
  const contentNode = $('.content', assistantNode);
  const statsNode = $('.msg-stats', assistantNode);
  scrollToBottom();

  setStreaming(true);
  const controller = new AbortController();
  state.controller = controller;
  let full = '';
  try {
    const res = await fetch('/api/chat', {
      method: 'POST', signal: controller.signal,
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ conversationId: state.current.id, content: text, attachments })
    });
    if (!res.ok || !res.body) throw new Error(`HTTP ${res.status}`);
    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buf = '';
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      buf += decoder.decode(value, { stream: true });
      const parts = buf.split('\n\n');
      buf = parts.pop();
      for (const part of parts) {
        const line = part.split('\n').find((l) => l.startsWith('data: '));
        if (!line) continue;
        let evt;
        try { evt = JSON.parse(line.slice(6)); } catch { continue; }
        if (evt.type === 'meta') {
          if (state.current && evt.conversationId) state.current.id = evt.conversationId;
          $('#chatTitle').textContent = evt.title || $('#chatTitle').textContent;
        } else if (evt.type === 'status') {
          statsNode.textContent = evt.message;
          scrollToBottom();
        } else if (evt.type === 'token') {
          full += evt.text;
          contentNode.innerHTML = renderMarkdown(full);
          statsNode.textContent = `${full.length} chars…`;
          scrollToBottom();
        } else if (evt.type === 'done') {
          full = evt.text || full;
          contentNode.innerHTML = renderMarkdown(full);
          contentNode.classList.remove('cursor');
          if (evt.stats) statsNode.textContent = `${evt.stats.completionTokens} tokens · ${(evt.stats.elapsedMs / 1000).toFixed(1)}s · ${evt.stats.tokensPerSecond} tok/s`;
          else statsNode.textContent = '';
        } else if (evt.type === 'saved') {
          if (state.current) state.current.title = evt.title ?? state.current.title;
        } else if (evt.type === 'error') {
          contentNode.classList.remove('cursor');
          contentNode.append(el('div', { class: 'msg-stats', style: 'color:#e5484d', text: `⚠️ ${evt.message}` }));
          statsNode.textContent = '';
          toast(evt.message, 'err');
        }
      }
    }
  } catch (err) {
    if (err.name !== 'AbortError') {
      contentNode.append(el('div', { class: 'msg-stats', style: 'color:#e5484d', text: `⚠️ ${err.message}` }));
      toast(err.message, 'err');
    } else {
      statsNode.textContent = 'stopped';
    }
  } finally {
    contentNode.classList.remove('cursor');
    setStreaming(false);
    state.controller = null;
    state.current = await api(`/api/conversations/${state.current.id}`).catch(() => state.current);
    renderChat();
    await loadConversations();
  }
}

function setStreaming(on) {
  state.streaming = on;
  $('#sendBtn').classList.toggle('recording', on);
  $('.send-ic').hidden = on;
  $('.stop-square').hidden = !on;
  $('#modelDot').className = 'dot ' + (on ? 'busy' : 'ok');
}

function stopGeneration() {
  state.controller?.abort();
  if (state.current) api('/api/chat/stop', { method: 'POST', body: { conversationId: state.current.id } }).catch(() => {});
}

function scrollToBottom(force = false) {
  const box = $('#messages');
  const near = box.scrollHeight - box.scrollTop - box.clientHeight < 160;
  if (force || near) box.scrollTop = box.scrollHeight;
  $('#scrollDownBtn').hidden = box.scrollHeight - box.scrollTop - box.clientHeight < 60;
}

/* ------------------------------------------------------------- attachments */

function renderAttachStrip() {
  const strip = $('#attachStrip');
  strip.innerHTML = '';
  strip.hidden = !state.attachments.length;
  for (const a of state.attachments) {
    const node = el('div', { class: 'att' },
      a.category === 'image' && a.preview ? el('img', { src: a.preview }) : el('span', { class: 'file-glyph', html: CATEGORY_ICON[a.category] ?? CATEGORY_ICON.other }),
      el('div', {},
        el('div', { text: a.name.length > 24 ? a.name.slice(0, 22) + '…' : a.name }),
        el('div', { class: 'st', text: a.status })
      ),
      el('div', { class: 'x', text: '×', onclick: () => { state.attachments = state.attachments.filter((x) => x.localId !== a.localId); renderAttachStrip(); } })
    );
    strip.append(node);
  }
}

async function uploadAttachment(file, { convertAudio = true } = {}) {
  const isAudio = file.type?.startsWith('audio/') || /\.(mp3|wav|m4a|ogg|oga|flac|aac|opus)$/i.test(file.name);
  const isVideo = file.type?.startsWith('video/');
  let blob = file, name = file.name || 'upload', type = file.type || 'application/octet-stream';
  const localId = Math.random().toString(36).slice(2);
  const entry = { localId, name, category: isAudio || isVideo ? 'audio' : (file.type?.startsWith('image/') ? 'image' : 'file'), status: 'uploading…', preview: file.type?.startsWith('image/') ? URL.createObjectURL(file) : null };
  state.attachments.push(entry);
  renderAttachStrip();
  try {
    if ((isAudio || isVideo) && convertAudio) {
      entry.status = 'decoding audio…'; renderAttachStrip();
      const wav = await toWav16k(file);
      blob = wav;
      name = name.replace(/\.[^.]+$/, '') + '.wav';
      type = 'audio/wav';
      entry.status = 'transcribing…';
    } else if (entry.category === 'image') entry.status = 'reading image…';
    else entry.status = 'reading file…';
    renderAttachStrip();

    const meta = await new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest();
      xhr.open('POST', `/api/uploads?name=${encodeURIComponent(name)}&type=${encodeURIComponent(type)}`);
      xhr.upload.onprogress = (e) => { entry.status = `uploading ${Math.round((e.loaded / e.total) * 100)}%`; renderAttachStrip(); };
      xhr.onload = () => xhr.status < 300 ? resolve(JSON.parse(xhr.responseText)) : reject(new Error(xhr.responseText || xhr.statusText));
      xhr.onerror = () => reject(new Error('upload failed'));
      xhr.send(blob);
    });
    Object.assign(entry, meta, { localId, status: meta.analysis?.ocr?.text ? 'text extracted' : meta.analysis?.asr?.text ? 'transcribed' : meta.analysis?.asr?.error ? 'no speech engine' : 'ready' });
  } catch (err) {
    entry.status = 'failed';
    toast(`${name}: ${err.message}`, 'err');
  }
  renderAttachStrip();
}

/** Decode any browser-supported audio/video into 16 kHz mono WAV (whisper-friendly). */
async function toWav16k(file) {
  const arrayBuf = await file.arrayBuffer();
  const AC = window.AudioContext || window.webkitAudioContext;
  const tmp = new AC();
  let audioBuf;
  try { audioBuf = await tmp.decodeAudioData(arrayBuf.slice(0)); } finally { tmp.close?.(); }
  const seconds = Math.min(audioBuf.duration, 60 * 20);
  const frames = Math.ceil(seconds * 16000);
  const offline = new OfflineAudioContext(1, frames, 16000);
  const src = offline.createBufferSource();
  src.buffer = audioBuf;
  src.connect(offline.destination);
  src.start();
  const rendered = await offline.startRendering();
  const data = rendered.getChannelData(0);
  const pcm = new Int16Array(data.length);
  for (let i = 0; i < data.length; i++) {
    const s = Math.max(-1, Math.min(1, data[i]));
    pcm[i] = s < 0 ? s * 0x8000 : s * 0x7fff;
  }
  const header = new ArrayBuffer(44);
  const view = new DataView(header);
  const writeStr = (off, str) => { for (let i = 0; i < str.length; i++) view.setUint8(off + i, str.charCodeAt(i)); };
  writeStr(0, 'RIFF'); view.setUint32(4, 36 + pcm.byteLength, true); writeStr(8, 'WAVE'); writeStr(12, 'fmt ');
  view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true);
  view.setUint32(24, 16000, true); view.setUint32(28, 32000, true); view.setUint16(32, 2, true); view.setUint16(34, 16, true);
  writeStr(36, 'data'); view.setUint32(40, pcm.byteLength, true);
  return new Blob([header, pcm.buffer], { type: 'audio/wav' });
}

async function toggleRecording() {
  if (state.recording) {
    state.recording.stop();
    return;
  }
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    const rec = new MediaRecorder(stream);
    const chunks = [];
    rec.ondataavailable = (e) => chunks.push(e.data);
    rec.onstop = async () => {
      stream.getTracks().forEach((t) => t.stop());
      state.recording = null;
      $('#micBtn').classList.remove('recording');
      const blob = new Blob(chunks, { type: rec.mimeType || 'audio/webm' });
      const file = new File([blob], `recording-${new Date().toISOString().slice(0, 19).replace(/[:T]/g, '-')}.webm`, { type: blob.type });
      await uploadAttachment(file);
      toast('Recording attached — press send to transcribe & ask');
    };
    rec.start();
    state.recording = rec;
    $('#micBtn').classList.add('recording');
    toast('Recording… click the mic again to stop');
  } catch (err) {
    toast('Microphone unavailable: ' + err.message, 'err');
  }
}

async function openLibrary() {
  const list = $('#libraryList');
  list.innerHTML = '<div class="muted">Loading…</div>';
  $('#libraryModal').hidden = false;
  const items = await api('/api/uploads').catch(() => []);
  list.innerHTML = '';
  if (!items.length) { list.append(el('div', { class: 'muted', text: 'Nothing uploaded yet — use + to add an image, audio file or document.' })); return; }
  for (const a of items) {
    const icon = CATEGORY_ICON[a.category] ?? CATEGORY_ICON.other;
    const extracted = a.analysis?.ocr?.text || a.analysis?.asr?.text || a.analysis?.text || '';
    const node = el('div', { class: 'model-item', style: 'cursor:pointer' },
      a.category === 'image' ? el('img', { src: `/api/files/${a.id}`, style: 'width:44px;height:44px;object-fit:cover;border-radius:8px' }) : el('span', { class: 'file-glyph big', html: icon }),
      el('div', { class: 'info' },
        el('div', { class: 'nm', text: a.name }),
        el('div', { class: 'sub' },
          el('span', { text: a.category }), el('span', { text: fmtBytes(a.size) }), el('span', { text: new Date(a.createdAt).toLocaleString() }),
          extracted ? el('span', { text: '· text ready' }) : null
        )
      ),
      el('button', { class: 'btn small', text: 'Attach', onclick: (e) => {
        e.stopPropagation();
        if (state.attachments.some((x) => x.id === a.id)) { toast('Already attached'); return; }
        state.attachments.push({ ...a, localId: a.id, status: extracted ? 'text ready' : 'ready' });
        renderAttachStrip();
        $('#libraryModal').hidden = true;
        toast(`Attached ${a.name}`);
      } })
    );
    list.append(node);
  }
}

function openViewer(a) {
  $('#viewerTitle').textContent = a.name;
  const body = $('#viewerBody');
  body.innerHTML = '';
  if (a.category === 'image') body.append(el('img', { src: `/api/files/${a.id}`, alt: a.name }));
  if (a.category === 'audio') body.append(el('audio', { controls: '', src: `/api/files/${a.id}` }));
  const meta = el('div', { class: 'muted small' });
  const bits = [];
  if (a.image?.width) bits.push(`${a.image.width}×${a.image.height}px`);
  if (a.audio?.durationSec) bits.push(`${a.audio.durationSec}s audio`);
  if (a.size) bits.push(fmtBytes(a.size));
  meta.textContent = bits.join(' · ');
  body.append(meta);
  const analysis = a.analysis ?? {};
  if (analysis.ocr?.text) body.append(el('h3', { text: `Text found in image (${analysis.ocr.provider})` }), el('pre', { text: analysis.ocr.text }));
  if (analysis.vision?.text) body.append(el('h3', { text: 'Image description' }), el('pre', { text: analysis.vision.text }));
  if (analysis.asr?.text) body.append(el('h3', { text: `Transcript (${analysis.asr.provider})` }), el('pre', { text: analysis.asr.text }));
  if (analysis.asr?.error) body.append(el('div', { class: 'muted', text: analysis.asr.error }));
  if (analysis.text) body.append(el('h3', { text: 'File contents' }), el('pre', { text: analysis.text.slice(0, 20000) }));
  if (!body.children.length) body.append(el('div', { class: 'muted', text: 'No analysis available.' }));
  $('#viewerModal').hidden = false;
}

/* -------------------------------------------------------------- models UI */

async function loadModels() {
  const data = await api('/api/models').catch(() => null);
  if (!data) return;
  state.models = data.models;
  state.curated = data.curated ?? [];
  const active = data.active;
  const activeModel = state.models.find((m) => m.id === active) ?? state.models[0];
  $('#modelChipLabel').textContent = activeModel ? (activeModel.meta?.sizeLabel ? `${activeModel.meta.sizeLabel} ${activeModel.meta.quantization ?? ''}` : activeModel.name) : 'No model';
  $('#modelBadge').textContent = state.models.length ? `${state.models.length} installed` : 'none';
  $('#modelDot').className = 'dot ' + (state.streaming ? 'busy' : state.models.length ? 'ok' : '');
  renderModelList();
}

function renderModelList() {
  const list = $('#modelList');
  if (!list) return;
  list.innerHTML = '';
  if (!state.models.length) list.append(el('div', { class: 'muted', text: 'No GGUF models in the models/ folder yet.' }));
  for (const m of state.models) {
    const isActive = state.health?.model?.id === m.id || state.models[0]?.id === m.id;
    const info = el('div', { class: 'info' },
      el('div', { class: 'nm', text: m.meta?.name || m.name }),
      el('div', { class: 'sub' },
        el('span', { text: fmtBytes(m.size) }),
        m.meta?.quantization ? el('span', { text: m.meta.quantization }) : null,
        m.meta?.sizeLabel ? el('span', { text: m.meta.sizeLabel }) : null,
        m.meta?.contextLength ? el('span', { text: `${(m.meta.contextLength / 1024).toFixed(0)}K ctx` }) : null
      )
    );
    list.append(el('div', { class: `model-item ${isActive ? 'active' : ''}` },
      info,
      el('button', { class: 'btn small ghost', text: 'Use', disabled: isActive ? '' : null, onclick: async (e) => {
        e.target.textContent = 'loading…';
        try { await api('/api/models/activate', { method: 'POST', body: { id: m.id } }); toast(`Loaded ${m.meta?.name || m.name}`); await loadModels(); await refreshHealth(); }
        catch (err) { toast(err.message, 'err'); } finally { e.target.textContent = 'Use'; }
      } }),
      el('button', { class: 'btn small ghost', text: 'Test', title: 'Run a quick self-test on this model', onclick: async (e) => {
        const btn = e.target;
        btn.disabled = true; btn.textContent = 'testing…';
        try {
          const r = await api('/api/models/test', { method: 'POST', body: { id: m.id } });
          toast(`${r.ok ? '✓ model answers correctly' : '⚠ unexpected answer'} — “${(r.output || '').slice(0, 60)}” (${r.stats ? r.stats.tokensPerSecond : '?'} tok/s)`, r.ok ? '' : 'err');
        } catch (err) { toast(err.message, 'err'); }
        btn.disabled = false; btn.textContent = 'Test';
        await loadModels(); await refreshHealth();
      } }),
      el('button', { class: 'btn small ghost', text: 'Delete', title: 'Delete model file', onclick: async () => {
        if (!confirm(`Delete ${m.name}?`)) return;
        await api(`/api/models/${encodeURIComponent(m.id)}`, { method: 'DELETE' });
        await loadModels();
      } })
    ));
  }
  const curated = $('#curatedList');
  if (curated) {
    curated.innerHTML = '';
    for (const c of state.curated) {
      curated.append(el('div', { class: 'model-item' },
        el('div', { class: 'info' },
          el('div', { class: 'nm', text: c.label }),
          el('div', { class: 'sub' }, el('span', { text: c.description }))
        ),
        el('button', { class: 'btn small', text: 'Download', onclick: (e) => startDownload({ curated: c.id }, e.target) })
      ));
    }
    const installed = new Set(state.models.map((m) => m.id));
    for (const c of state.curated) if (c.id.includes('.gguf') && installed.has(c.id)) { /* already there */ }
  }
}

async function startDownload(payload, btn) {
  $('#dlProgress').hidden = false;
  btn && (btn.disabled = true);
  try {
    const { id } = await api('/api/models/download', { method: 'POST', body: payload });
    const tick = setInterval(async () => {
      const st = await api(`/api/models/download/${id}`).catch(() => null);
      if (!st) return;
      const pct = st.total ? Math.min(100, (st.received / st.total) * 100) : 0;
      $('#dlBar').style.width = pct + '%';
      $('#dlText').textContent = `${st.status} · ${fmtBytes(st.received)}${st.total ? ' / ' + fmtBytes(st.total) : ''}${st.speed ? ` · ${fmtBytes(st.speed)}/s` : ''}${st.error ? ' · ' + st.error : ''}`;
      if (['done', 'error', 'cancelled'].includes(st.status)) {
        clearInterval(tick);
        btn && (btn.disabled = false);
        if (st.status === 'done') { toast(`Model ready: ${st.name}`); await loadModels(); await refreshHealth(); setTimeout(() => ($('#dlProgress').hidden = true), 2500); }
        else toast(`Download failed: ${st.error}`, 'err');
      }
    }, 900);
  } catch (err) {
    toast(err.message, 'err');
    btn && (btn.disabled = false);
  }
}

async function uploadGguf(file) {
  const CHUNK = 8 * 1024 * 1024;
  $('#dlProgress').hidden = false;
  try {
    for (let offset = 0; offset < file.size; offset += CHUNK) {
      const blob = file.slice(offset, Math.min(offset + CHUNK, file.size));
      const done = offset + CHUNK >= file.size;
      const url = `/api/models/upload?name=${encodeURIComponent(file.name)}&offset=${offset}&done=${done ? 1 : 0}`;
      const res = await fetch(url, { method: 'POST', body: blob });
      if (!res.ok) throw new Error((await res.json().catch(() => ({}))).error || `HTTP ${res.status}`);
      const pct = Math.min(100, ((offset + blob.size) / file.size) * 100);
      $('#dlBar').style.width = pct + '%';
      $('#dlText').textContent = `importing ${pct.toFixed(1)}% · ${fmtBytes(offset + blob.size)} / ${fmtBytes(file.size)}`;
    }
    $('#dlText').textContent = 'model imported ✓';
    toast('Model imported');
    await loadModels();
  } catch (err) {
    toast('Import failed: ' + err.message, 'err');
    $('#dlText').textContent = 'import failed: ' + err.message;
  }
}

/* --------------------------------------------------------------- settings */

function fillSettingsForm(s) {
  $('#setSystem').value = s.systemPrompt ?? '';
  const bind = (id, val, labelId, fmt = (v) => v) => {
    $(id).value = val;
    if (labelId) $(labelId).textContent = fmt(val);
    $(id).oninput = () => { if (labelId) $(labelId).textContent = fmt($(id).value); };
    if (labelId) $(labelId).textContent = fmt(val);
  };
  bind('#setTemp', s.temperature, '#tempVal');
  bind('#setMaxTok', s.maxTokens, '#maxTokVal');
  bind('#setTopK', s.topK, '#topKVal');
  bind('#setTopP', s.topP, '#topPVal');
  bind('#setRep', s.repeatPenalty, '#repVal');
  bind('#setCtx', s.contextSize, '#ctxVal', (v) => `${v} tokens`);
  $('#setThreads').value = s.threads;
  $('#setWrapper').value = s.chatWrapper ?? 'auto';
  $('#setOcr').value = s.ocrProvider ?? 'auto';
  $('#setAsr').value = s.asrProvider ?? 'auto';
  $('#setVision').value = s.visionProvider ?? 'auto';
  $('#setBaseUrl').value = s.cloud?.baseUrl ?? '';
  $('#setApiKey').value = '';
  $('#setApiKey').placeholder = s.cloud?.apiKey ? `saved (${s.cloud.apiKey})` : 'sk-…';
  $('#setVisionModel').value = s.cloud?.visionModel ?? '';
  $('#setAsrModel').value = s.cloud?.asrModel ?? '';
}

let provisionToastShown = false;

async function refreshHealth() {
  state.health = await api('/api/health').catch(() => null);
  if (!state.health) return;
  const prov = state.health.provisioning;
  if (prov && !['done', 'error', 'cancelled'].includes(prov.status)) {
    const pct = prov.total ? Math.min(100, (prov.received / prov.total) * 100).toFixed(0) + '%' : fmtBytes(prov.received);
    $('#hintCaps').textContent = `installing the on-board model… ${pct}`;
    if (!provisionToastShown) {
      provisionToastShown = true;
      toast('First run: installing the Qwen 1.5B (Q4_K_M) on-board model — the UI keeps working while it downloads.');
    }
    updateEmptyMeta();
    return;
  }
  if (prov && prov.status === 'done' && provisionToastShown && !state.models.length) {
    provisionToastShown = false;
    toast('On-board model installed ✓');
    await loadModels();
  }
  if (prov && prov.status === 'error' && provisionToastShown) {
    provisionToastShown = false;
    toast('Automatic model install failed — open Models to retry or import a GGUF.', 'err');
  }
  const caps = state.health.capabilities ?? {};
  const parts = [];
  parts.push(caps.ocr?.rapidocr || caps.ocr?.tesseractWasm ? 'image reading on' : 'image reading off');
  parts.push(caps.asr?.whisperCpp ? 'speech-to-text on' : 'speech-to-text needs setup');
  $('#hintCaps').textContent = parts.join(' · ');
  updateEmptyMeta();
  if (state.health.settings) state.settings = { ...state.settings, ...state.health.settings };
}

/* ------------------------------------------------------- PWA / phone install */

let deferredInstall = null;

async function registerServiceWorker() {
  if (!('serviceWorker' in navigator)) return;
  if (location.protocol !== 'https:' && !['localhost', '127.0.0.1'].includes(location.hostname)) return; // SW needs a secure context
  try {
    const reg = await navigator.serviceWorker.register('/sw.js', { scope: '/' });
    reg.addEventListener('updatefound', () => {});
  } catch (err) { console.warn('service worker registration failed:', err.message); }
}

function setupInstallPrompt() {
  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault();
    deferredInstall = e;
    $('#pwaInstallBtn').hidden = false;
    $('#installBtn').classList.add('highlight');
  });
  window.addEventListener('appinstalled', () => {
    deferredInstall = null;
    $('#pwaInstallBtn').hidden = true;
    $('#installBtn').classList.remove('highlight');
    toast('Installed — open Kocharian from your home screen.');
  });
}

async function openPhoneModal() {
  const url = $('#phoneUrl');
  const img = $('#qrImg');
  const note = $('#phoneNote');
  $('#phoneModal').hidden = false;
  url.textContent = location.origin;

  let net = null;
  try { net = await api('/api/network'); } catch { /* offline-ish */ }
  const isLocalhost = ['localhost', '127.0.0.1', '::1'].includes(location.hostname);
  // prefer a LAN address when the page is opened on the computer itself
  const target = (isLocalhost && net?.lan?.length) ? net.lan[0].url : location.origin;
  url.textContent = target;
  img.src = `/api/network/qr.svg?data=${encodeURIComponent(target)}`;
  img.onerror = () => { img.replaceWith(el('div', { class: 'muted small', text: 'QR unavailable — copy the link instead.' })); };

  const insecure = location.protocol !== 'https:' && !isLocalhost;
  note.textContent = insecure
    ? 'Heads-up: over plain http:// a phone can still browse and add the app to its home screen, but the offline cache and the automatic "Install" prompt need https (or localhost).'
    : (net?.lan?.length ? `Other addresses: ${net.lan.map((l) => l.url).join(', ')}` : 'Only this address is reachable — the phone must be on the same network.');
  $('#pwaInstallBtn').hidden = !deferredInstall;
  $('#copyUrlBtn').onclick = async () => {
    try { await navigator.clipboard.writeText(url.textContent); toast('Link copied'); }
    catch { toast('Copy failed — select the link manually', 'err'); }
  };
  $('#pwaInstallBtn').onclick = async () => {
    if (!deferredInstall) return;
    deferredInstall.prompt();
    const { outcome } = await deferredInstall.userChoice;
    if (outcome === 'accepted') { toast('Installing…'); deferredInstall = null; $('#pwaInstallBtn').hidden = true; }
  };
  // iOS has no install prompt — nudge with the exact steps
  if (/iPhone|iPad|iPod/.test(navigator.userAgent) && !window.navigator.standalone) {
    $('#pwaInstallBtn').hidden = true;
    note.textContent = 'On iPhone: tap Share ⬆ in Safari, then "Add to Home Screen".';
  }
}

/* ------------------------------------------------------------------- boot */

function autoGrow() {
  const ta = $('#input');
  ta.style.height = 'auto';
  ta.style.height = Math.min(ta.scrollHeight, 220) + 'px';
}

/** Keep the composer above the on-screen keyboard (iOS/Android). */
function setupViewportFix() {
  const vv = window.visualViewport;
  if (!vv) return;
  const sync = () => {
    document.documentElement.style.setProperty('--vvh', `${Math.round(vv.height)}px`);
    if (document.activeElement?.id === 'input') setTimeout(() => scrollToBottom(true), 60);
  };
  vv.addEventListener('resize', sync);
  vv.addEventListener('scroll', sync);
  sync();
}

function applyTheme(theme) {
  document.documentElement.dataset.theme = theme;
  $('#themeLabel').textContent = theme === 'dark' ? 'Dark theme' : 'Light theme';
  localStorage.setItem('kocharian-theme', theme);
}

async function boot() {
  applyTheme(localStorage.getItem('kocharian-theme') || 'dark');

  // events
  $('#newChatBtn').onclick = () => newChat().then(closeSidebar);
  $('#brandBtn').onclick = () => { newChat().then(closeSidebar); };
  $('#menuBtn').onclick = () => { $('#sidebar').classList.add('open'); $('#scrim').classList.add('show'); };
  $('#collapseBtn').onclick = closeSidebar;
  $('#scrim').onclick = closeSidebar;
  $('#searchInput').oninput = (e) => { state.filter = e.target.value; renderConversations(); };
  $('#composer').onsubmit = (e) => { e.preventDefault(); state.streaming ? stopGeneration() : send(); };
  $('#sendBtn').onclick = (e) => { e.preventDefault(); state.streaming ? stopGeneration() : send(); };
  $('#input').addEventListener('input', autoGrow);
  $('#input').addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) { e.preventDefault(); state.streaming ? stopGeneration() : send(); }
  });
  $('#attachBtn').onclick = () => $('#filePicker').click();
  $('#libraryBtn').onclick = openLibrary;
  $('#installBtn').onclick = openPhoneModal;
  $('#filePicker').onchange = async (e) => { for (const f of e.target.files) await uploadAttachment(f); e.target.value = ''; };
  $('#micBtn').onclick = toggleRecording;
  $('#scrollDownBtn').onclick = () => scrollToBottom(true);
  $('#messages').addEventListener('scroll', () => scrollToBottom());

  // drag & drop + paste
  const main = $('#main');
  main.addEventListener('dragover', (e) => { e.preventDefault(); main.classList.add('dragover'); });
  main.addEventListener('dragleave', () => main.classList.remove('dragover'));
  main.addEventListener('drop', async (e) => {
    e.preventDefault(); main.classList.remove('dragover');
    for (const f of e.dataTransfer.files) await uploadAttachment(f);
  });
  document.addEventListener('paste', async (e) => {
    const items = [...(e.clipboardData?.files ?? [])];
    if (items.length) { e.preventDefault(); for (const f of items) await uploadAttachment(f); }
  });

  // modals
  for (const btn of $$('[data-close]')) btn.onclick = () => btn.closest('.modal').hidden = true;
  for (const m of $$('.modal')) m.addEventListener('click', (e) => { if (e.target === m) m.hidden = true; });
  $('#modelsBtn').onclick = async () => { await loadModels(); $('#modelsModal').hidden = false; };
  $('#modelChip').onclick = async () => { await loadModels(); $('#modelsModal').hidden = false; };
  $('#settingsBtn').onclick = async () => { fillSettingsForm(await api('/api/settings')); $('#settingsModal').hidden = false; };
  $('#themeBtn').onclick = () => { const next = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark'; applyTheme(next); api('/api/settings', { method: 'POST', body: { theme: next } }).catch(() => {}); };
  $('#hfDownloadBtn').onclick = () => {
    const repo = $('#hfRepo').value.trim(), file = $('#hfFile').value.trim();
    if (!repo || !file) return toast('Enter a repo and a file name', 'err');
    startDownload({ source: 'huggingface', repo, file, name: file, mirrors: [{ source: 'hfmirror', repo, file }] }, $('#hfDownloadBtn'));
  };
  $('#ggufUpload').onchange = (e) => { const f = e.target.files[0]; if (f) uploadGguf(f); };
  $('#saveSettings').onclick = async () => {
    const patch = {
      systemPrompt: $('#setSystem').value,
      temperature: Number($('#setTemp').value), maxTokens: Number($('#setMaxTok').value),
      topK: Number($('#setTopK').value), topP: Number($('#setTopP').value), repeatPenalty: Number($('#setRep').value),
      contextSize: Number($('#setCtx').value), threads: Number($('#setThreads').value), chatWrapper: $('#setWrapper').value,
      ocrProvider: $('#setOcr').value, asrProvider: $('#setAsr').value, visionProvider: $('#setVision').value,
      cloud: { baseUrl: $('#setBaseUrl').value, visionModel: $('#setVisionModel').value, asrModel: $('#setAsrModel').value }
    };
    if ($('#setApiKey').value.trim()) patch.cloud.apiKey = $('#setApiKey').value.trim();
    try {
      state.settings = await api('/api/settings', { method: 'POST', body: patch });
      toast('Settings saved');
      $('#settingsModal').hidden = true;
      await refreshHealth();
    } catch (err) { toast(err.message, 'err'); }
  };
  $('#resetSettings').onclick = async () => {
    if (!confirm('Reset settings to defaults?')) return;
    const s = await api('/api/settings', { method: 'POST', body: { resetAll: true } }).catch(() => null);
    fillSettingsForm(s ?? {});
  };

  // chat actions
  $('#renameBtn').onclick = async () => {
    if (!state.current) return;
    const t = prompt('Chat name', state.current.title);
    if (t) { await api(`/api/conversations/${state.current.id}`, { method: 'PATCH', body: { title: t } }); state.current.title = t; $('#chatTitle').textContent = t; await loadConversations(); }
  };
  $('#deleteChatBtn').onclick = async () => {
    if (!state.current) return;
    if (!confirm('Delete this chat?')) return;
    await api(`/api/conversations/${state.current.id}`, { method: 'DELETE' });
    state.current = null; renderChat(); await loadConversations();
  };
  $('#exportBtn').onclick = () => {
    if (!state.current) return;
    const lines = [`# ${state.current.title}`, '', `_Exported from Kocharian AI — ${new Date().toLocaleString()}_`, ''];
    for (const m of state.current.messages ?? []) {
      lines.push(`## ${m.role === 'user' ? 'You' : 'Kocharian AI'}${m.createdAt ? ` · ${new Date(m.createdAt).toLocaleString()}` : ''}`, '', m.content, '');
      for (const a of m.attachments ?? []) {
        lines.push(`> [attachment] ${a.name} (${a.category})`, '');
        if (a.analysis?.ocr?.text) lines.push('OCR:', '```', a.analysis.ocr.text, '```', '');
        if (a.analysis?.asr?.text) lines.push('Transcript:', '```', a.analysis.asr.text, '```', '');
      }
    }
    const blob = new Blob([lines.join('\n')], { type: 'text/markdown' });
    const a = el('a', { href: URL.createObjectURL(blob), download: `${state.current.title.replace(/[^\w -]/g, '') || 'chat'}.md` });
    a.click();
  };
  document.addEventListener('keydown', (e) => {
    if (e.ctrlKey && e.key.toLowerCase() === 'k') { e.preventDefault(); $('#searchInput').focus(); }
    if (e.ctrlKey && e.key.toLowerCase() === 'n') { e.preventDefault(); newChat(); }
    if (e.key === 'Escape') { for (const m of $$('.modal')) m.hidden = true; }
  });

  // data
  registerServiceWorker();
  setupInstallPrompt();
  setupViewportFix();

  // manifest shortcuts: /?new=1 and /?panel=models
  const params = new URLSearchParams(location.search);
  if (params.has('new')) setTimeout(() => newChat(), 400);
  if (params.get('panel') === 'models') setTimeout(() => { loadModels().then(() => ($('#modelsModal').hidden = false)); }, 600);

  await refreshHealth();
  await loadModels();
  await loadConversations();
  const last = state.conversations[0];
  if (last) await openConversation(last.id); else renderChat();
  autoGrow();
  setInterval(() => { const p = state.health?.provisioning; refreshHealth(); if (p && !['done', 'error', 'cancelled'].includes(p.status)) setTimeout(refreshHealth, 2500); }, 15000);
}

document.addEventListener('DOMContentLoaded', boot);
