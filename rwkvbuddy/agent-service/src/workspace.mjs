import { readdir, readFile, lstat, realpath } from 'node:fs/promises';
import { resolve, join, relative, extname } from 'node:path';
import { createHash } from 'node:crypto';
import { spawn } from 'node:child_process';
import { checkAbort } from './runtime.mjs';

export const skip = new Set(['node_modules', 'build', 'dist', 'runs', 'vendor', 'target', 'runtime']);
export const extensions = new Set(['.md', '.txt', '.csv', '.tsv', '.json', '.jsonl', '.yaml', '.yml', '.dart', '.ts', '.js', '.mjs', '.py', '.toml', '.tsx', '.jsx', '.html', '.css', '.swift', '.kt', '.java', '.cpp', '.cc', '.c', '.h', '.rs', '.go', '.sh']);
export const hash = (text) => createHash('sha256').update(text).digest('hex');

// Root documentation, manifests and entry points should reach the model before fixtures.
export const manifestNames = /^(pubspec\.yaml|package\.json|Cargo\.toml|pyproject\.toml|go\.mod|CMakeLists\.txt|Podfile|Dockerfile)$/i;
export function sourcePriority(path) {
  const parts = path.split('/');
  const name = parts.at(-1);
  if (parts.length === 1 && /^readme(?:\.|$)/i.test(name)) return 0;
  if (parts.length === 1 && manifestNames.test(name)) return 1;
  if (/(^|\/)(fixtures?|tests?|examples?|samples?)(\/|$)/i.test(path)) return 8;
  if (manifestNames.test(name)) return 2;
  if (/^(lib|src|app)\/(main|index|app)\./i.test(path) || /^(main|index|app|service)\./i.test(name)) return 3;
  if (/^readme(?:\.|$)/i.test(name)) return 4;
  if (/^(lib|src|app)\//i.test(path)) return 5;
  return 6;
}

// Use Git's ignore rules when available, including rules inherited from a parent repo.
// Non-Git directories and machines without Git retain the normal filename exclusions.
export async function ignoredPaths(root, paths, signal) {
  if (!paths.length) return new Set();
  checkAbort(signal);
  return new Promise((resolveIgnored, reject) => {
    const child = spawn('git', ['check-ignore', '--stdin', '-z'], { cwd: root, windowsHide: true, stdio: ['pipe', 'pipe', 'ignore'] });
    let output = '';
    const timer = setTimeout(() => child.kill(), 5000);
    const abort = () => child.kill();
    signal?.addEventListener('abort', abort, { once: true });
    child.stdout.setEncoding('utf8');
    child.stdout.on('data', (chunk) => { output += chunk; });
    child.stdin.on('error', () => {});
    child.on('error', () => {});
    child.on('close', (code) => {
      clearTimeout(timer);
      signal?.removeEventListener('abort', abort);
      if (signal?.aborted) { reject(new DOMException('任务已取消', 'AbortError')); return; }
      const ignored = code === 0 || code === 1 ? new Set(output.split('\0').filter(Boolean)) : new Set();
      // An explicitly selected ignored directory (e.g. bundled demo under build/)
      // is its own analysis root; an ancestor's blanket ignore must not hide all of it.
      resolveIgnored(ignored.has('.') ? new Set() : ignored);
    });
    child.stdin.end(['.', ...paths].join('\0') + '\0');
  });
}

export async function scanWorkspace(path, signal, send = () => {}) {
  const root = await realpath(resolve(path));
  const files = {};
  const warnings = [];
  const candidates = [];
  const directories = [{ path: root, depth: 0 }];
  let visited = 0;
  let limited = false;
  for (let index = 0; index < directories.length && !limited; index++) {
    checkAbort(signal);
    const dir = directories[index];
    const entries = (await readdir(dir.path, { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name));
    for (const entry of entries) {
      checkAbort(signal);
      if (++visited > 12000) { limited = true; warnings.push('目录项超过 12000，扫描已停止。'); break; }
      if (entry.name.startsWith('.') || skip.has(entry.name)) continue;
      const full = join(dir.path, entry.name);
      const stat = await lstat(full);
      if (stat.isSymbolicLink()) continue;
      if (stat.isDirectory()) {
        if (dir.depth < 12) directories.push({ path: full, depth: dir.depth + 1 });
        continue;
      }
      if (!stat.isFile() || (!extensions.has(extname(entry.name).toLowerCase()) && !manifestNames.test(entry.name))) continue;
      if (/(secret|credential|token|password|private[-_]?key|^default-connection\.json$)/i.test(entry.name)) continue;
      candidates.push({ full, name: relative(root, full).replaceAll('\\', '/'), size: stat.size });
    }
  }
  const ignored = await ignoredPaths(root, candidates.map((file) => file.name), signal);
  candidates.sort((a, b) => sourcePriority(a.name) - sourcePriority(b.name) || a.name.split('/').length - b.name.split('/').length || a.name.localeCompare(b.name));
  let total = 0;
  for (const file of candidates) {
    checkAbort(signal);
    if (ignored.has(file.name)) continue;
    if (file.size > 256 * 1024) { warnings.push(`${file.name} 超过 256 KB，未读取。`); continue; }
    if (total + file.size > 4 * 1024 * 1024 || Object.keys(files).length >= 240) {
      warnings.push('已达到 240 个文本文件或 4 MB 的扫描上限。'); break;
    }
    const buffer = await readFile(file.full);
    if (buffer.includes(0)) continue;
    total += buffer.length;
    const content = buffer.toString('utf8').replace(/^\uFEFF/, '');
    files[file.name] = { content, hash: hash(content), lines: content.split(/\r?\n/).length };
    send('input.file_parsed', { name: file.name, path: file.name, lines: files[file.name].lines, bytes: buffer.length,
      source: 'directory', summary: `已读入快照：${file.name} · ${files[file.name].lines} 行` });
  }
  if (!Object.keys(files).length) throw new Error('此目录没有可分析的文本文件，请选择工作目录或使用内置样例。');
  send('input.scan_completed', { fileCount: Object.keys(files).length, warnings, summary: `目录读取完成：${Object.keys(files).length} 个文本文件` });
  const inputHashes = Object.fromEntries(Object.entries(files).map(([path, file]) => [path, file.hash]));
  return { root, files, warnings, inputHashes, snapshotHash: hash(JSON.stringify(inputHashes)) };
}

const labels = { north: '北辰科技', east: '江南制造', west: '西岭能源' };
function decimal(value, scale = 2) {
  const text = String(value).trim();
  if (!new RegExp(`^-?\\d+(?:\\.\\d{1,${scale}})?$`).test(text)) throw new Error(`无效数字：${text.slice(0, 40)}`);
  const negative = text.startsWith('-');
  const [whole, fraction = ''] = text.replace('-', '').split('.');
  const number = BigInt(whole) * 10n ** BigInt(scale) + BigInt(fraction.padEnd(scale, '0'));
  if (number > 100000000000000n) throw new Error('金额超过支持范围');
  return Number(negative ? -number : number);
}
export function financeSnapshot(snapshot) {
  const companies = [];
  const cash = [];
  const warnings = [...snapshot.warnings];
  const evidence = [];
  const add = (path, start, end, label) => {
    const id = `E${evidence.length + 1}`;
    evidence.push({ id, path, start, end, label, hash: snapshot.files[path].hash });
    return id;
  };
  // This parser supports only the sample schema at the selected root, never nested projects/fixtures.
  const rootLedger = Object.keys(snapshot.files).some((path) => /^jobs\/co-[^/]+\/ledger\.csv$/.test(path));
  if (!rootLedger) return { companies, cash, warnings, evidence, isFinance: false };
  const taxPath = snapshot.files['shared/tax_rates.tsv'] ? 'shared/tax_rates.tsv' : undefined;
  const rates = new Map();
  let taxEvidence;
  if (taxPath) {
    taxEvidence = add(taxPath, 1, snapshot.files[taxPath].lines, '所得税率与核算口径');
    for (const line of snapshot.files[taxPath].content.replaceAll('\\t', '\t').split(/\r?\n/).slice(1).filter((s) => s.trim())) {
      const [entity, rate] = line.split('\t');
      if (rates.has(entity)) throw new Error(`税率表存在重复主体：${entity}`);
      const basisPoints = decimal(rate, 4);
      if (basisPoints < 0 || basisPoints > 10000) throw new Error(`税率必须在 0 到 1 之间：${entity}`);
      rates.set(entity, basisPoints);
    }
  }
  for (const [path, file] of Object.entries(snapshot.files)) {
    const match = path.match(/^jobs\/co-([^/]+)\/ledger\.csv$/);
    if (match) {
      const entity = match[1];
      if (!rates.has(entity)) throw new Error(`${entity} 缺少税率，请补充 shared/tax_rates.tsv`);
      const lines = file.content.trim().split(/\r?\n/);
      if (lines[0].trim() !== 'account,amount') throw new Error(`${path} 表头应为 account,amount`);
      let revenue = 0; let cost = 0;
      const omitted = new Set();
      for (const [index, line] of lines.slice(1).entries()) {
        if (!line.trim()) continue;
        const parts = line.split(',');
        if (parts.length !== 2) throw new Error(`${path}:${index + 2} 不是支持的两列台账格式`);
        const [account, value] = parts;
        const cents = decimal(value);
        if (['sales', 'service'].includes(account)) revenue += cents;
        else if (['cogs', 'opex'].includes(account)) cost += cents;
        else omitted.add(account);
      }
      if (!Number.isSafeInteger(revenue) || !Number.isSafeInteger(cost)) throw new Error('台账合计超过精度范围');
      const rate = rates.get(entity);
      // Round half away from zero using integer arithmetic.
      const numerator = BigInt(revenue - cost) * BigInt(10000 - rate);
      const profit = Number((numerator < 0n ? -1n : 1n) * ((numerator < 0n ? -numerator : numerator) + 5000n) / 10000n);
      const evidenceId = add(path, 1, lines.length, `${labels[entity] || entity}台账`);
      companies.push({ entity, label: labels[entity] || entity, revenue, cost, rate, profit, evidenceIds: [evidenceId, taxEvidence] });
      if (omitted.size) warnings.push(`${labels[entity] || entity}：核算仅含 sales/service、cogs/opex，未计入 ${[...omitted].join('、')}。`);
    }
    if (path === 'jobs/group-cash/cash.jsonl') {
      const lines = file.content.trim().split(/\r?\n/);
      const item = { inflow: 0, outflow: 0, inflowCount: 0, outflowCount: 0, ignored: 0, parties: new Set() };
      for (const [index, line] of lines.entries()) {
        if (!line.trim()) continue;
        let record;
        try { record = JSON.parse(line); } catch { throw new Error(`${path}:${index + 1} JSON 格式错误`); }
        if (record.status !== 'posted') { item.ignored++; continue; }
        if (!['in', 'out'].includes(record.kind) || !record.counterparty) throw new Error(`${path}:${index + 1} 缺少有效 kind/counterparty`);
        const cents = decimal(record.amount);
        if (cents < 0) throw new Error(`${path}:${index + 1} 金额须为非负数，用 kind 表示收支`);
        if (record.kind === 'in') { item.inflow += cents; item.inflowCount++; }
        else { item.outflow += cents; item.outflowCount++; }
        item.parties.add(record.counterparty);
      }
      if (!Number.isSafeInteger(item.inflow) || !Number.isSafeInteger(item.outflow)) throw new Error('资金合计超过精度范围');
      cash.push({ ...item, net: item.inflow - item.outflow, parties: item.parties.size, evidenceIds: [add(path, 1, lines.length, '已入账资金流水')] });
      if (item.ignored) warnings.push(`${path}：${item.ignored} 笔非 posted 记录未纳入计算。`);
    }
  }
  return { companies, cash, warnings, evidence, isFinance: companies.length > 0 || cash.length > 0 };
}

export function workspaceFacts(snapshot) {
  const evidence = Object.entries(snapshot.files).sort(([a], [b]) => sourcePriority(a) - sourcePriority(b) || a.split('/').length - b.split('/').length || a.localeCompare(b)).map(([path, file], index) => ({
    id: `E${index + 1}`, path, start: 1, end: file.lines, hash: file.hash, label: path,
    ...(file.originalPath ? { originalPath: file.originalPath, extracted: file.extracted } : {}),
  }));
  const excerptLimit = snapshot.attachments ? Math.min(12000, Math.floor(60000 / evidence.length)) : 1600;
  const facts = evidence.map((source) => ({ ...source, excerpt: snapshot.files[source.path].content.slice(0, excerptLimit) }));
  const warnings = [...snapshot.warnings];
  if (Object.values(snapshot.files).some((file) => file.content.length > excerptLimit)) warnings.push(`初始分析提供每个文件的前 ${excerptLimit} 个字符。${snapshot.attachments ? '完整提取文本已保存在任务 inputs 目录。' : '未通读超出片段的内容。'}`);
  if (!snapshot.attachments && facts.length > 45) warnings.push('模型仅接收前 45 个文件片段，优先 README、工程配置及入口代码；其余文件可通过资料工具按需读取。');
  return { evidence, files: facts, warnings, sourceMode: snapshot.textOnly ? 'text' : snapshot.attachments ? 'files' : 'directory' };
}
export function money(cents) {
  const value = BigInt(cents);
  const absolute = value < 0n ? -value : value;
  return `${value < 0n ? '-' : ''}${(absolute / 100n).toLocaleString('en-US')}.${String(absolute % 100n).padStart(2, '0')}`;
}
