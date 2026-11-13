import { readdir, readFile, lstat, realpath } from 'node:fs/promises';
import { resolve, join, relative, extname } from 'node:path';
import { createHash } from 'node:crypto';
import { checkAbort } from './runtime.mjs';

const skip = new Set(['node_modules', 'build', 'dist', 'runs', 'vendor', 'target', 'runtime']);
const extensions = new Set(['.md', '.txt', '.csv', '.tsv', '.json', '.jsonl', '.yaml', '.yml', '.dart', '.ts', '.js', '.mjs', '.py', '.toml']);
export const hash = (text) => createHash('sha256').update(text).digest('hex');

export async function scanWorkspace(path, signal) {
  const root = await realpath(resolve(path));
  const files = {};
  const warnings = [];
  let total = 0;
  let visited = 0;
  let exhausted = false;
  const walk = async (dir, depth = 0) => {
    checkAbort(signal);
    if (depth > 12 || exhausted) return;
    const entries = (await readdir(dir, { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name));
    for (const entry of entries) {
      checkAbort(signal);
      if (++visited > 12000) { exhausted = true; warnings.push('目录项超过 12000，扫描已停止。'); break; }
      if (entry.name.startsWith('.') || skip.has(entry.name)) continue;
      const full = join(dir, entry.name);
      const stat = await lstat(full);
      if (stat.isSymbolicLink()) continue;
      if (stat.isDirectory()) { await walk(full, depth + 1); continue; }
      if (!stat.isFile() || !extensions.has(extname(entry.name).toLowerCase())) continue;
      if (/(secret|credential|token|password|private[-_]?key)/i.test(entry.name)) continue;
      if (stat.size > 256 * 1024) { warnings.push(`${relative(root, full)} 超过 256 KB，未读取。`); continue; }
      if (total + stat.size > 4 * 1024 * 1024 || Object.keys(files).length >= 240) {
        exhausted = true; warnings.push('已达到 240 个文本文件或 4 MB 的扫描上限。'); break;
      }
      const buffer = await readFile(full);
      if (buffer.includes(0)) continue;
      total += buffer.length;
      const name = relative(root, full).replaceAll('\\', '/');
      const content = buffer.toString('utf8').replace(/^\uFEFF/, '');
      files[name] = { content, hash: hash(content), lines: content.split(/\r?\n/).length };
    }
  };
  await walk(root);
  if (!Object.keys(files).length) throw new Error('此目录没有可分析的文本文件，请选择工作目录或使用内置样例。');
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
  const taxPath = Object.keys(snapshot.files).find((p) => p.endsWith('tax_rates.tsv'));
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
    if (path.endsWith('cash.jsonl')) {
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
  const evidence = Object.entries(snapshot.files).map(([path, file], index) => ({
    id: `E${index + 1}`, path, start: 1, end: file.lines, hash: file.hash, label: path,
    ...(file.originalPath ? { originalPath: file.originalPath, extracted: file.extracted } : {}),
  }));
  const excerptLimit = snapshot.attachments ? Math.min(12000, Math.floor(60000 / evidence.length)) : 1600;
  const facts = evidence.map((source) => ({ ...source, excerpt: snapshot.files[source.path].content.slice(0, excerptLimit) }));
  const warnings = [...snapshot.warnings];
  if (Object.values(snapshot.files).some((file) => file.content.length > excerptLimit)) warnings.push(`专家分析每个文件的前 ${excerptLimit} 个字符。${snapshot.attachments ? '完整提取文本已保存在任务 inputs 目录。' : '未通读超出片段的内容。'}`);
  if (!snapshot.attachments && facts.length > 45) warnings.push('模型仅接收前 45 个文件片段与本地检查结果，未通读所有文件。');
  return { evidence, files: facts, warnings, sourceMode: snapshot.textOnly ? 'text' : snapshot.attachments ? 'files' : 'directory' };
}
export function money(cents) {
  const value = BigInt(cents);
  const absolute = value < 0n ? -value : value;
  return `${value < 0n ? '-' : ''}${(absolute / 100n).toLocaleString('en-US')}.${String(absolute % 100n).padStart(2, '0')}`;
}
