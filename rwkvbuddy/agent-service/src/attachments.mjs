import { Worker } from 'node:worker_threads';
import { lstat, readFile, mkdir, writeFile, realpath } from 'node:fs/promises';
import { basename, extname, join, resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { checkAbort, abortError } from './runtime.mjs';

export const attachmentExtensions = new Set(['.pdf', '.docx', '.xlsx', '.txt', '.md', '.csv', '.tsv', '.json', '.jsonl', '.yaml', '.yml', '.dart', '.ts', '.js', '.mjs', '.py', '.toml']);
const hash = (value) => createHash('sha256').update(value).digest('hex');
function extract(bytes, extension, signal) {
  checkAbort(signal);
  return new Promise((resolveResult, reject) => {
    const worker = new Worker(new URL('./document-worker.mjs', import.meta.url), {
      workerData: { bytes, extension }, resourceLimits: { maxOldGenerationSizeMb: 192 },
      stdout: true, stderr: true,
    });
    worker.stdout.resume(); worker.stderr.resume();
    let finished = false;
    const finish = (error, result) => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      signal?.removeEventListener('abort', cancel);
      void worker.terminate();
      if (error) reject(error); else resolveResult(result);
    };
    const cancel = () => finish(abortError());
    const timer = setTimeout(() => finish(new Error('文件解析超过 30 秒，请拆分或转换后重试')), 30000);
    signal?.addEventListener('abort', cancel, { once: true });
    if (signal?.aborted) cancel();
    worker.once('message', (result) => finish(result.error ? new Error(result.error) : null, result));
    worker.once('error', (error) => finish(new Error(`解析失败：${error.message}`)));
    worker.once('exit', () => { if (!finished) finish(new Error('文档解析进程提前退出')); });
  });
}
function decodeText(bytes) {
  if (bytes[0] === 0xff && bytes[1] === 0xfe) return new TextDecoder('utf-16le', { fatal: true }).decode(bytes);
  if (bytes[0] === 0xfe && bytes[1] === 0xff) return new TextDecoder('utf-16be', { fatal: true }).decode(bytes);
  if (bytes.includes(0)) throw new Error('此文件包含二进制内容，无法作为文本读取');
  try { return new TextDecoder('utf-8', { fatal: true }).decode(bytes); }
  catch { throw new Error('文本编码不支持，请另存为 UTF-8 后重试'); }
}
export async function readAttachments(paths, directory, signal, send = () => {}) {
  if (!Array.isArray(paths) || !paths.length || paths.length > 20) throw new Error('请选择 1–20 个文件');
  const files = {};
  const attachments = [];
  const warnings = [];
  const seen = new Set();
  let totalBytes = 0;
  let textBytes = 0;
  const inputDirectory = join(directory, 'inputs');
  await mkdir(inputDirectory, { recursive: true });
  for (const [index, source] of paths.entries()) {
    checkAbort(signal);
    const name = basename(source);
    const attachment = { name, originalPath: resolve(source), status: 'reading' };
    attachments.push(attachment);
    send('input.file_started', { name, summary: `正在读取：${name}` });
    try {
      const stat = await lstat(source);
      if (!stat.isFile() || stat.isSymbolicLink()) throw new Error('请选择普通文件');
      const canonical = await realpath(source);
      const key = process.platform === 'win32' ? canonical.toLowerCase() : canonical;
      if (seen.has(key)) throw new Error('重复文件，已跳过');
      seen.add(key);
      const extension = extname(name).toLowerCase();
      if (!attachmentExtensions.has(extension)) throw new Error('暂不支持此格式，请转换为 PDF、DOCX、XLSX 或文本');
      if (stat.size > 10 * 1024 * 1024) throw new Error('单文件超过 10 MB');
      if (totalBytes + stat.size > 20 * 1024 * 1024) throw new Error('本次文件总大小超过 20 MB');
      const bytes = await readFile(source);
      totalBytes += bytes.length;
      const parsed = ['.pdf', '.docx', '.xlsx'].includes(extension) ? await extract(bytes, extension, signal)
        : { content: decodeText(bytes), warnings: [] };
      checkAbort(signal);
      const content = parsed.content.replace(/^\uFEFF/, '').replaceAll('\r\n', '\n');
      const size = Buffer.byteLength(content, 'utf8');
      if (!content.trim()) throw new Error('文件没有可分析的文字');
      if (size > 1024 * 1024) throw new Error('单文件提取文本超过 1 MB，请拆分后重试');
      if (textBytes + size > 4 * 1024 * 1024) throw new Error('本次提取文本超过 4 MB，请减少文件');
      textBytes += size;
      const snapshotName = `${String(index + 1).padStart(2, '0')}-${name}.txt`;
      const id = `${String(index + 1).padStart(2, '0')}/${name}`;
      const metadata = { content, hash: hash(bytes), textHash: hash(content), originalPath: canonical,
        lines: content.split('\n').length, extracted: ['.pdf', '.docx', '.xlsx'].includes(extension) };
      await writeFile(join(inputDirectory, snapshotName), content, 'utf8');
      files[id] = metadata;
      Object.assign(attachment, { status: 'parsed', bytes: bytes.length, hash: metadata.hash, textHash: metadata.textHash,
        snapshot: `inputs/${snapshotName}`, lines: metadata.lines, warnings: parsed.warnings });
      warnings.push(...parsed.warnings.map((warning) => `${name}：${warning}`));
      send('input.file_parsed', { ...attachment, summary: `已读取：${name} · ${metadata.lines} 行文字` });
    } catch (error) {
      if (signal?.aborted) throw error;
      Object.assign(attachment, { status: 'rejected', error: error.message });
      warnings.push(`${name} 未纳入分析：${error.message}`);
      send('input.file_rejected', { ...attachment, summary: `${name} 未纳入分析：${error.message}` });
    }
  }
  await writeFile(join(inputDirectory, 'manifest.json'), JSON.stringify(attachments, null, 2));
  send('input.completed', { attachments, summary: `资料读取完成：${Object.keys(files).length} 个成功，${attachments.filter((item) => item.status === 'rejected').length} 个未纳入` });
  if (!Object.keys(files).length) throw new Error(`没有可分析的文件。${warnings.join('；')}`);
  const inputHashes = Object.fromEntries(Object.entries(files).map(([path, file]) => [path, file.hash]));
  return { root: '', files, warnings, attachments, inputHashes, snapshotHash: hash(JSON.stringify(inputHashes)) };
}
