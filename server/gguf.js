// Minimal, dependency-free GGUF metadata reader (header + key/value pairs only).
// Used to show model info (name, architecture, quantization, context length...) without loading weights.
import { open } from 'node:fs/promises';

const TYPES = { 0: ['u8', 1], 1: ['i8', 1], 2: ['u16', 2], 3: ['i16', 2], 4: ['u32', 4], 5: ['i32', 4], 6: ['f32', 4], 7: ['bool', 1], 8: ['string', 0], 9: ['array', 0], 10: ['u64', 8], 11: ['i64', 8], 12: ['f64', 8] };

const QUANT_NAMES = {
  0: 'F32', 1: 'F16', 2: 'Q4_0', 3: 'Q4_1', 7: 'Q8_0', 8: 'Q5_0', 9: 'Q5_1', 10: 'Q2_K', 11: 'Q3_K_S', 12: 'Q3_K_M',
  13: 'Q3_K_L', 14: 'Q4_K_S', 15: 'Q4_K_M', 16: 'Q5_K_S', 17: 'Q5_K_M', 18: 'Q6_K', 19: 'IQ2_XXS', 20: 'IQ2_XS',
  21: 'Q2_K_S', 22: 'IQ3_XS', 23: 'IQ3_XXS', 24: 'IQ1_S', 25: 'IQ4_NL', 26: 'IQ3_S', 27: 'IQ2_S', 28: 'IQ4_XS',
  29: 'IQ1_M', 30: 'BF16', 31: 'Q4_0_4_4', 32: 'Q4_0_4_8', 33: 'Q4_0_8_8', 34: 'TQ1_0', 35: 'TQ2_0', 36: 'IQ4_NL_4_4'
};

class Reader {
  constructor(buf) { this.b = buf; this.p = 0; }
  need(n) { if (this.p + n > this.b.length) throw new Error('EOF'); }
  u32() { this.need(4); const v = this.b.readUInt32LE(this.p); this.p += 4; return v; }
  u64() { this.need(8); const v = Number(this.b.readBigUInt64LE(this.p)); this.p += 8; return v; }
  i32() { this.need(4); const v = this.b.readInt32LE(this.p); this.p += 4; return v; }
  i64() { this.need(8); const v = Number(this.b.readBigInt64LE(this.p)); this.p += 8; return v; }
  f32() { this.need(4); const v = this.b.readFloatLE(this.p); this.p += 4; return v; }
  f64() { this.need(8); const v = this.b.readDoubleLE(this.p); this.p += 8; return v; }
  str() { const n = this.u64(); this.need(n); const s = this.b.toString('utf8', this.p, this.p + n); this.p += n; return s; }
  bytes(n) { this.need(n); const s = this.b.subarray(this.p, this.p + n); this.p += n; return s; }
  scalar(t) {
    switch (t) {
      case 0: return this.bytes(1)[0];
      case 1: { const b = this.bytes(1); return b.readInt8(0); }
      case 2: { const b = this.bytes(2); return b.readUInt16LE(0); }
      case 3: { const b = this.bytes(2); return b.readInt16LE(0); }
      case 4: return this.u32();
      case 5: return this.i32();
      case 6: return this.f32();
      case 7: return !!this.bytes(1)[0];
      case 10: return this.u64();
      case 11: return this.i64();
      case 12: return this.f64();
      default: throw new Error('unsupported value type ' + t);
    }
  }
  /** array: read the element type + length, then consume (and lightly summarise) the payload */
  array() {
    const elemType = this.u32();
    const n = this.u64();
    if (elemType === 8) {
      const out = [];
      for (let i = 0; i < n; i++) {
        const sv = this.str();
        if (i < 12 && out.length < 12) out.push(sv);
      }
      return n > out.length ? out.concat([`\u2026 +${n - out.length} more`]) : out;
    }
    if (elemType === 9) { for (let i = 0; i < n; i++) this.array(); return `<${n} nested arrays>`; }
    const size = TYPES[elemType]?.[1];
    if (!size) throw new Error('unsupported array element type ' + elemType);
    this.need(size * n);
    this.p += size * n;
    return `<${n} ${TYPES[elemType][0]}>`;
  }
  value(t) {
    if (t === 8) return this.str();
    if (t === 9) return this.array();
    return this.scalar(t);
  }
}

function withTimeout(promise, ms) {
  return Promise.race([promise, new Promise((_, rej) => setTimeout(() => rej(new Error('timeout')), ms))]);
}

/** Read GGUF metadata from a file. Returns null when the file is not a readable GGUF. */
export async function readGgufMeta(file, { budget = 96 * 1024 * 1024 } = {}) {
  let fh;
  try {
    fh = await open(file, 'r');
    const head = Buffer.alloc(24);
    if ((await fh.read(head, 0, 24, 0)).bytesRead < 24) return null;
    if (head.toString('ascii', 0, 4) !== 'GGUF') return null;
    const version = head.readUInt32LE(4);
    const nTensors = Number(head.readBigUInt64LE(8));
    const nKv = Number(head.readBigUInt64LE(16));

    // read the metadata section (grows as needed, capped)
    let size = Math.min(1024 * 1024, Math.max(65536, 1024));
    let buf;
    for (;;) {
      buf = Buffer.alloc(size);
      await fh.read(buf, 0, size, 0);
      try {
        const r = new Reader(buf);
        r.p = 24;
        const kv = {};
        for (let i = 0; i < nKv; i++) {
          const key = r.str();
          const type = r.u32();
          kv[key] = r.value(type);
        }
        return summarize(kv, { version, nTensors, nKv, metadataBytes: r.p });
      } catch (err) {
        if (err.message === 'EOF' && size < budget) { size = Math.min(size * 2, budget); continue; }
        if (err.message === 'EOF') return null;
        throw err;
      }
    }
  } catch {
    return null;
  } finally {
    await fh?.close().catch(() => {});
  }
}

function summarize(kv, info) {
  const arch = kv['general.architecture'] || 'unknown';
  const fileType = kv['general.file_type'];
  const meta = {
    ...info,
    architecture: arch,
    name: kv['general.name'] || null,
    basename: kv['general.basename'] || null,
    sizeLabel: kv['general.size_label'] || null,
    finetune: kv['general.finetune'] || null,
    quantization: QUANT_NAMES[fileType] || (fileType != null ? `type ${fileType}` : null),
    parameterCount: kv['general.parameter_count'] ?? null,
    contextLength: kv[`${arch}.context_length`] ?? null,
    embeddingLength: kv[`${arch}.embedding_length`] ?? null,
    blockCount: kv[`${arch}.block_count`] ?? null,
    headCount: kv[`${arch}.attention.head_count`] ?? null,
    headCountKv: kv[`${arch}.attention.head_count_kv`] ?? null,
    vocabSize: Array.isArray(kv['tokenizer.ggml.tokens']) ? Number(String(kv['tokenizer.ggml.tokens'].slice(-1)[0]).replace(/\D/g, '')) || null : null,
    chatTemplate: typeof kv['tokenizer.chat_template'] === 'string' ? 'present' : null,
    isVision: !!(kv['clip.has_vision_encoder'] ?? kv['vision.embedding_length']),
    extra: Object.fromEntries(Object.entries(kv).filter(([k]) => !k.startsWith('tokenizer.ggml.')))
  };
  delete meta.extra['general.name'];
  return meta;
}

export const ggufQuantNames = QUANT_NAMES;
