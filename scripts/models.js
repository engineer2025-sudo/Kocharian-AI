#!/usr/bin/env node
/**
 * Kocharian AI - model provisioning helper.
 *
 *   node scripts/models.js                     list installed + curated models
 *   node scripts/models.js --meta <file.gguf>  print GGUF metadata
 *   node scripts/models.js --curated <id>      download a curated model (Hugging Face, mirrors, or PyPI-chunks fallback)
 *   node scripts/models.js --hf <repo> <file>  download any GGUF from Hugging Face
 *   node scripts/models.js --url <url> [name]  download any direct GGUF url
 */
import path from 'node:path';
import { createWriteStream } from 'node:fs';
import { promises as fs } from 'node:fs';
import { pipeline } from 'node:stream/promises';
import { Readable } from 'node:stream';
import { execFileSync } from 'node:child_process';
import { readGgufMeta } from '../server/gguf.js';

const ROOT = path.resolve(import.meta.dirname, '..');
const MODELS_DIR = path.join(ROOT, 'models');
const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const after = (name) => args[args.indexOf(name) + 1];

const CURATED = {
  'qwen1_5-1_5b-chat-q4_k_m.gguf': [
    { url: 'https://huggingface.co/Qwen/Qwen1.5-1.5B-Chat-GGUF/resolve/main/qwen1_5-1_5b_chat_q4_k_m.gguf?download=true' },
    { url: 'https://hf-mirror.com/Qwen/Qwen1.5-1.5B-Chat-GGUF/resolve/main/qwen1_5-1_5b_chat_q4_k_m.gguf?download=true' },
    { url: 'https://modelscope.cn/models/qwen/Qwen1.5-1.5B-Chat-GGUF/resolve/master/qwen1_5_1_5b_chat_q4_k_m.gguf' },
    { pypi: 'tinymentor-model-part' } // offline fallback: chunked PyPI packages holding a Qwen 1.5B-instruct Q4_K_M GGUF
  ],
  'qwen2.5-coder-1.5b-instruct-q4_k_m.gguf': [
    { url: 'https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf?download=true' },
    { pypi: 'tinymentor-model-part' }
  ]
};

const fmt = (b) => b > 1e9 ? (b / 1e9).toFixed(2) + ' GB' : (b / 1e6).toFixed(1) + ' MB';

async function list() {
  await fs.mkdir(MODELS_DIR, { recursive: true });
  const files = (await fs.readdir(MODELS_DIR)).filter((f) => f.endsWith('.gguf'));
  console.log('\nInstalled models:');
  if (!files.length) console.log('  (none)');
  for (const f of files) {
    const st = await fs.stat(path.join(MODELS_DIR, f));
    const meta = await readGgufMeta(path.join(MODELS_DIR, f), { budget: 16 * 1024 * 1024 });
    console.log(`  • ${f}  ${fmt(st.size)}  ${meta ? `[${meta.architecture} ${meta.quantization ?? ''} ${meta.sizeLabel ?? ''}]` : ''}`);
  }
  console.log('\nCurated downloads (node scripts/models.js --curated <id>):');
  for (const id of Object.keys(CURATED)) console.log(`  • ${id}`);
  console.log('');
}

async function download(url, dest) {
  const res = await fetch(url, { redirect: 'follow' });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const total = Number(res.headers.get('content-length') || 0);
  let got = 0, last = Date.now(), lastBytes = 0;
  process.stdout.write(`  downloading ${url.slice(0, 90)}…\n`);
  await pipeline(Readable.fromWeb(res.body), async function* (src) {
    for await (const chunk of src) {
      got += chunk.length;
      const now = Date.now();
      if (now - last > 1000) {
        const speed = (got - lastBytes) / ((now - last) / 1000);
        process.stdout.write(`\r  ${fmt(got)}${total ? ' / ' + fmt(total) : ''}  ${fmt(speed)}/s   `);
        last = now; lastBytes = got;
      }
      yield chunk;
    }
  }, createWriteStream(dest));
  process.stdout.write('\r  done.                            \n');
}

async function pypiChunks(prefix, dest) {
  const tmp = await fs.mkdtemp(path.join(ROOT, 'tmp', 'chunks-'));
  const wheels = [];
  for (let i = 1; i <= 22; i++) {
    const pkg = `${prefix}${i}`;
    const meta = await (await fetch(`https://pypi.org/pypi/${pkg}/json`)).json();
    const url = meta?.urls?.[0]?.url;
    if (!url) throw new Error(`PyPI package ${pkg} not found`);
    const file = path.join(tmp, `${pkg}.whl`);
    process.stdout.write(`\r  part ${i}/22 …`);
    await download(url, file);
    wheels.push(file);
  }
  process.stdout.write('\r  assembling parts…            \n');
  const script = `
import sys, zipfile, os, json
out = sys.argv[1]
written = 0
with open(out, 'wb') as w:
    for p in sys.argv[2:]:
        z = zipfile.ZipFile(p)
        names = [i for i in z.infolist() if not i.is_dir() and i.file_size > 100000]
        if not names:
            raise SystemExit('no payload found in ' + p)
        entry = max(names, key=lambda i: i.file_size)
        with z.open(entry) as f:
            while True:
                b = f.read(1 << 22)
                if not b:
                    break
                w.write(b)
                written += len(b)
print(json.dumps({"ok": True, "size": os.path.getsize(out), "payload": written}))
`;
  execFileSync('python3', ['-c', script, dest, ...wheels]);
  await fs.rm(tmp, { recursive: true, force: true });
}

async function main() {
  await fs.mkdir(path.join(ROOT, 'tmp'), { recursive: true });
  if (flag('--meta')) {
    const meta = await readGgufMeta(after('--meta'));
    console.log(JSON.stringify(meta, null, 2));
    return;
  }
  if (flag('--hf')) {
    const [repo, file] = [after('--hf'), args[args.indexOf('--hf') + 2]];
    const dest = path.join(MODELS_DIR, path.basename(file));
    await download(`https://huggingface.co/${repo}/resolve/main/${file}?download=true`, dest);
    console.log('saved', dest);
    return;
  }
  if (flag('--url')) {
    const url = after('--url');
    const name = args[args.indexOf('--url') + 2] || path.basename(new URL(url).pathname);
    const dest = path.join(MODELS_DIR, name);
    await download(url, dest);
    console.log('saved', dest);
    return;
  }
  if (flag('--curated')) {
    const id = after('--curated');
    const sources = CURATED[id];
    if (!sources) { console.error(`Unknown curated id. Options: ${Object.keys(CURATED).join(', ')}`); process.exit(1); }
    const dest = path.join(MODELS_DIR, id);
    for (const src of sources) {
      try {
        if (src.pypi) await pypiChunks(src.pypi, dest);
        else await download(src.url, dest);
        const meta = await readGgufMeta(dest, { budget: 16 * 1024 * 1024 });
        if (!meta?.architecture) throw new Error('not a valid GGUF');
        console.log(`✓ ${id} ready — ${meta.name ?? meta.architecture} ${meta.quantization ?? ''}`);
        return;
      } catch (err) {
        console.log(`  source failed: ${err.message}`);
        await fs.rm(dest, { force: true }).catch(() => {});
      }
    }
    console.error('All sources failed. You can still import a GGUF manually (Models → Import GGUF file).');
    process.exit(1);
  }
  await list();
}

main().catch((err) => { console.error(err); process.exit(1); });
