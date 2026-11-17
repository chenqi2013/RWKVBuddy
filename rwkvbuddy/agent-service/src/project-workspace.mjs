import { readdir, lstat, realpath, open } from 'node:fs/promises';
import { resolve, join, relative, extname, dirname, basename, isAbsolute } from 'node:path';
import { skip, extensions, manifestNames, sourcePriority, ignoredPaths, hash } from './workspace.mjs';
import { calculate } from './analysis-tools.mjs';
import { checkAbort } from './runtime.mjs';

export function promptWorkspace(question) {
  const text = question.trim();
  const quoted = text.match(/^["'`]((?:\/|[A-Za-z]:[\\/]).+?)["'`]/);
  if (quoted) return quoted[1];
  if (!/^(?:\/(?!\/)|[A-Za-z]:[\\/])/.test(text)) return '';
  return text.split(/[\r\n]|\s+(?=[\u3400-\u9fff])|[，,；;]/)[0].replace(/\\$/, '').trimEnd();
}
export async function resolveProjectPath(path) {
  try { const root = await realpath(resolve(path)); if (!(await lstat(root)).isDirectory()) throw new Error('不是目录'); return { root, corrected: false }; } catch (error) {
    const clean = path.replace(/\\$/, '');
    const parent = dirname(resolve(clean));
    const names = await readdir(parent).catch(() => []);
    const matches = names.filter((name) => name.trimEnd() === basename(clean).trimEnd());
    if (matches.length === 1) {
      const root = await realpath(join(parent, matches[0]));
      if ((await lstat(root)).isDirectory()) return { root, corrected: root !== resolve(path) };
    }
    throw new Error(`目录不存在或无法访问：${path}。请检查路径或重新选择目录。`);
  }
}
export async function indexProject(path, signal, send = () => {}) {
  const { root } = await resolveProjectPath(path);
  const index = {};
  const warnings = [];
  const queue = [{ path: '', depth: 0 }];
  let visited = 0;
  outer: for (const dir of queue) {
    checkAbort(signal);
    let entries;
    try {
      const directoryPath = join(root, dir.path);
      if (await realpath(directoryPath) !== directoryPath) { warnings.push(`跳过已变化的目录：${dir.path}`); continue; }
      entries = await readdir(directoryPath, { withFileTypes: true });
    }
    catch { warnings.push(`无法索引目录：${dir.path}`); continue; }
    entries.sort((a, b) => a.name.localeCompare(b.name));
    const visible = entries.filter((e) => !e.name.startsWith('.') && !skip.has(e.name) && !/(secret|credential|token|password|private[-_]?key|^default-connection\.json$)/i.test(e.name));
    const ignored = await ignoredPaths(root, visible.map((e) => join(dir.path, e.name).replaceAll('\\', '/')), signal);
    for (const entry of visible) {
      checkAbort(signal);
      if (++visited > 20000) { warnings.push('目录索引达到 20000 项上限；未索引的内容无法读取。'); break outer; }
      const name = join(dir.path, entry.name).replaceAll('\\', '/');
      if (ignored.has(name) || entry.isSymbolicLink()) continue;
      if (entry.isDirectory()) {
        index[name] = { type: 'directory' };
        if (dir.depth < 16) queue.push({ path: name, depth: dir.depth + 1 });
        else warnings.push(`已达到目录深度上限：${name}`);
      } else if (entry.isFile()) {
        const stat = await lstat(join(root, name));
        index[name] = { type: 'file', bytes: stat.size, readable: extensions.has(extname(name).toLowerCase()) || manifestNames.test(entry.name) };
      }
    }
  }
  send('input.indexed', { root, entryCount: Object.keys(index).length, warnings, summary: '目录索引完成；文件正文将按需读取' });
  return { project: true, root, index, files: {}, warnings, inputHashes: {}, snapshotHash: hash(JSON.stringify(index)) };
}
const bounded = (n, fallback, max) => Math.max(1, Math.min(max, Math.floor(Number(n) || fallback)));
function localPath(value = '.') {
  if (typeof value !== 'string' || isAbsolute(value) || value.split(/[\\/]/).includes('..')) throw new Error('请使用工作区内的相对路径，不能使用 .. 或绝对路径');
  return value.replaceAll('\\', '/').replace(/^\.\//, '').replace(/\/$/, '') || '.';
}
function page(items, args, max = 100) {
  const offset = Math.max(0, Math.floor(Number(args.offset) || 0));
  const limit = bounded(args.limit, 40, max);
  const entries = items.slice(offset, offset + limit);
  return { entries, total: items.length, offset, hasMore: offset + limit < items.length, nextOffset: offset + limit < items.length ? offset + limit : null };
}
async function content(snapshot, path, signal) {
  checkAbort(signal);
  if (snapshot.files[path]) return snapshot.files[path];
  if (!snapshot.index[path]?.readable) throw new Error(`文件未索引或不支持文本读取：${path}。请用 find_files 确认路径。`);
  const full = join(snapshot.root, path);
  const actual = await realpath(full);
  if (relative(snapshot.root, actual).startsWith('..') || isAbsolute(relative(snapshot.root, actual)) || actual !== full) throw new Error('路径已变化或含符号链接，请重新选择目录');
  if ((await ignoredPaths(snapshot.root, [path], signal)).has(path)) throw new Error('文件已被忽略，无法读取');
  const handle = await open(actual, 'r');
  let buffer;
  try {
    const bytes = Buffer.alloc(1024 * 1024 + 1);
    let length = 0;
    while (length < bytes.length) {
      checkAbort(signal);
      const count = await handle.read(bytes, length, bytes.length - length, length);
      if (!count.bytesRead) break;
      length += count.bytesRead;
    }
    if (length > 1024 * 1024) throw new Error('文件超过 1 MB，请选择更小的文本文件');
    buffer = bytes.subarray(0, length);
  } finally { await handle.close(); }
  checkAbort(signal);
  if (buffer.includes(0)) throw new Error('文件为二进制格式，无法按文本读取');
  const total = Object.values(snapshot.files).reduce((sum, f) => sum + Buffer.byteLength(f.content), 0);
  if (total + buffer.length > 16 * 1024 * 1024) throw new Error('本轮读取达到 16 MB 上限，请缩小搜索范围');
  const text = buffer.toString('utf8').replace(/^\uFEFF/, '');
  snapshot.files[path] = { content: text, hash: hash(text), lines: text.split(/\r?\n/).length };
  snapshot.inputHashes[path] = hash(text);
  snapshot.snapshotHash = hash(JSON.stringify(snapshot.inputHashes));
  return snapshot.files[path];
}
function cite(evidence, path, file, start, end) {
  let source = evidence.find((e) => e.path === path);
  if (!source) { source = { id: `E${evidence.length + 1}`, path, start, end, hash: file.hash, label: path, ranges: [] }; evidence.push(source); }
  source.start = Math.min(source.start, start); source.end = Math.max(source.end, end);
  if (!source.ranges.some((range) => range.start === start && range.end === end)) source.ranges.push({ start, end });
  return source.id;
}
export function projectOverview(snapshot) {
  const paths = Object.keys(snapshot.index);
  return { entryCount: paths.length, rootEntries: page(paths.filter((p) => !p.includes('/')).map((path) => ({ path, ...snapshot.index[path] })), {}, 60),
    keyFiles: paths.filter((p) => snapshot.index[p].readable).sort((a, b) => sourcePriority(a) - sourcePriority(b) || a.localeCompare(b)).slice(0, 30),
    note: '仅目录元数据；尚未向模型提供文件正文。请调用工具探索。' };
}
export async function projectTool(name, args, snapshot, evidence, signal) {
  checkAbort(signal);
  if (!args || typeof args !== 'object' || Array.isArray(args)) throw new Error('工具参数须为对象');
  if (name === 'calculator') return calculate(args.expression);
  if (name === 'read_file') {
    const path = localPath(args.path ?? evidence.find((e) => e.id === args.evidenceId)?.path);
    const file = await content(snapshot, path, signal);
    const lines = file.content.split(/\r?\n/);
    const start = bounded(args.startLine, 1, Math.max(1, lines.length + 1));
    if (start > lines.length) throw new Error(`起始行超出文件范围，共 ${lines.length} 行`);
    const count = bounded(args.lineCount, 100, 200);
    const selected = [];
    let chars = 0;
    for (const line of lines.slice(start - 1, start - 1 + count)) {
      if (chars + line.length > 16000 && selected.length) break;
      if (line.length > 16000) throw new Error('单行超过 16000 字符，请用 search_text 定位内容');
      selected.push(line); chars += line.length + 1;
    }
    const end = start + selected.length - 1;
    return { path, evidenceId: cite(evidence, path, file, start, end), startLine: start, endLine: end, totalLines: lines.length,
      text: selected.join('\n'), hasMore: end < lines.length, nextStartLine: end < lines.length ? end + 1 : null };
  }
  const dir = localPath(args.path ?? '.');
  if (dir !== '.' && snapshot.index[dir]?.type !== 'directory') throw new Error(`目录未索引：${dir}。请用 list_directory 确认路径。`);
  const prefix = dir === '.' ? '' : `${dir}/`;
  const paths = Object.keys(snapshot.index).filter((p) => p.startsWith(prefix));
  if (name === 'list_directory') return { path: dir, ...page(paths.filter((p) => !p.slice(prefix.length).includes('/')).sort().map((path) => ({ path, ...snapshot.index[path] })), args) };
  if (name === 'find_files') {
    const pattern = String(args.pattern || '*');
    if (pattern.length > 200) throw new Error('文件名模式过长');
    const regex = new RegExp(pattern.split('*').map((part) => part.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('.*'), 'i');
    return { path: dir, pattern, ...page(paths.filter((p) => snapshot.index[p].type === 'file' && regex.test(p)).sort().map((path) => ({ path, ...snapshot.index[path] })), args) };
  }
  if (name === 'search_text') {
    if (typeof args.query !== 'string' || !args.query.trim() || args.query.length > 200) throw new Error('搜索词须为 1–200 个字符');
    const files = paths.filter((p) => snapshot.index[p].readable).sort();
    const offset = Math.max(0, Math.floor(Number(args.offset) || 0));
    const matches = []; const errors = [];
    let cursor = offset, scannedFiles = 0, bytes = 0;
    const limit = bounded(args.limit, 24, 50);
    for (; cursor < files.length && scannedFiles < 80 && bytes < 2 * 1024 * 1024; cursor++) {
      checkAbort(signal);
      const path = files[cursor];
      let file;
      try { file = await content(snapshot, path, signal); } catch (error) { checkAbort(signal); errors.push({ path, error: error.message }); continue; }
      scannedFiles++; bytes += Buffer.byteLength(file.content);
      const hits = file.content.split(/\r?\n/).flatMap((text, i) => text.toLowerCase().includes(args.query.toLowerCase()) ? [{ line: i + 1, text: text.slice(0, 500) }] : []);
      const remaining = limit - matches.length;
      for (const hit of hits.slice(0, remaining)) matches.push({ path, evidenceId: cite(evidence, path, file, hit.line, hit.line), ...hit });
      if (matches.length >= limit) { cursor++; if (hits.length > remaining) errors.push({ path, error: '此文件匹配过多，请 read_file 查看完整上下文' }); break; }
    }
    return { path: dir, query: args.query, matches, scannedFiles, totalFiles: files.length, errors: errors.slice(0, 10), hasMore: cursor < files.length, nextOffset: cursor < files.length ? cursor : null,
      note: 'offset 按文件分页；匹配仅展示命中行片段，需 read_file 核对上下文。' };
  }
  throw new Error('未知工具。支持 list_directory、find_files、read_file、search_text、calculator');
}
