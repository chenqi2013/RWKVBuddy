import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { AgentRun } from '../src/engine.mjs';
import { readAttachments } from '../src/attachments.mjs';
import { docxFixture, xlsxFixture, pdfFixture } from './document-fixtures.mjs';

async function scratch(t) {
  const root = await mkdtemp(join(tmpdir(), 'rwkvbuddy-files-'));
  t.after(async () => {
    assert.equal(dirname(resolve(root)), resolve(tmpdir()));
    assert.ok(root.split(/[\\/]/).at(-1).startsWith('rwkvbuddy-files-'));
    await rm(root, { recursive: true, force: true });
  });
  return root;
}
const command = (paths) => ({ question: '分析上传文件中的预算、销售数据和风险', workspace: '', mode: 'local', sourceMode: 'files', selectedFiles: paths });
test('selected PDF, DOCX, XLSX and Unicode text produce a report using only actual attachments', async (t) => {
  const root = await scratch(t);
  const inputs = [ ['合同 说明.docx', docxFixture()], ['销售.xlsx', xlsxFixture()], ['客户.pdf', pdfFixture()], ['会议.txt', '会议决议：采购金额 9876 元。'] ];
  const paths = [];
  for (const [name, content] of inputs) { const path = join(root, name); paths.push(path); await writeFile(path, content); }
  const events = [];
  const run = new AgentRun(command(paths), join(root, 'runs'), (event) => events.push(event));
  const state = await run.execute();
  assert.equal(state.status, 'completed', state.error);
  assert.equal(state.attachments.filter((item) => item.status === 'parsed').length, 4);
  assert.deepEqual(state.artifacts, []);
  assert.deepEqual(state.roles, []);
  for (const value of ['客户项目说明 & 风险', '12345', '销售明细', 'B1=1200.50', '含税收入', 'B1-B2', '7890', '9876']) assert.ok(state.report.includes(value), value);
  assert.ok(!state.report.includes('北辰科技'));
  assert.ok(state.report.includes('提取文本行号'));
  assert.equal(events.filter((event) => event.type === 'input.file_parsed').length, 4);
  const manifest = JSON.parse(await readFile(join(run.directory, 'inputs/manifest.json'), 'utf8'));
  assert.equal(manifest.length, 4);
  await writeFile(paths[0], 'source changed');
  const preserved = await readFile(join(run.directory, manifest[0].snapshot), 'utf8');
  assert.ok(preserved.includes('12345'));
});
test('duplicate basenames remain distinct; invalid attachments yield a partial report with reasons', async (t) => {
  const root = await scratch(t);
  await mkdir(join(root, 'a')); await mkdir(join(root, 'b'));
  const paths = [join(root, 'a/报告.txt'), join(root, 'b/报告.txt'), join(root, '坏文件.pdf'), join(root, '旧版.doc')];
  for (const [index, path] of paths.entries()) await writeFile(path, ['第一份收入 111', '第二份收入 222', 'bad pdf', 'unsupported'][index]);
  const state = await new AgentRun(command(paths), join(root, 'runs'), () => {}).execute();
  assert.equal(state.status, 'partial');
  assert.equal(state.evidence.length, 2);
  assert.notEqual(state.evidence[0].path, state.evidence[1].path);
  assert.ok(state.report.includes('111') && state.report.includes('222'));
  assert.equal(state.attachments.filter((item) => item.status === 'rejected').length, 2);
  assert.ok(state.report.includes('未纳入'));
});
test('all invalid or missing attachments fail explicitly without using built-in sample', async (t) => {
  const root = await scratch(t);
  const state = await new AgentRun(command([join(root, 'missing.txt')]), join(root, 'runs'), () => {}).execute();
  assert.equal(state.status, 'failed');
  assert.equal(state.artifacts.length, 0);
  assert.equal(state.attachments[0].status, 'rejected');
  assert.ok(state.error.includes('没有可分析的文件'));
});
test('attachment count, UTF-16 decoding, file size and cancellation are enforced', async (t) => {
  const root = await scratch(t);
  await assert.rejects(readAttachments(Array(21).fill('x'), root), /1–20/);
  const utf16 = join(root, '记事本.txt');
  await writeFile(utf16, Buffer.concat([Buffer.from([0xff, 0xfe]), Buffer.from('中文金额 123', 'utf16le')]));
  const big = join(root, '超限.txt'); await writeFile(big, Buffer.alloc(10 * 1024 * 1024 + 1, 65));
  const data = await readAttachments([utf16, big], join(root, 'data'));
  assert.ok(Object.values(data.files)[0].content.includes('中文金额'));
  assert.equal(data.attachments[1].status, 'rejected');
  assert.match(data.attachments[1].error, /10 MB/);
  const controller = new AbortController(); controller.abort();
  await assert.rejects(readAttachments([utf16], root, controller.signal), { name: 'AbortError' });
});
