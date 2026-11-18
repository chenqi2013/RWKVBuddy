import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createDeliverables } from '../src/deliverables.mjs';
import { readAttachments } from '../src/attachments.mjs';
import { AgentRun } from '../src/engine.mjs';

async function scratch(t) {
  const root = await mkdtemp(join(tmpdir(), 'rwkvbuddy-delivery-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  return root;
}

test('generated Word and Excel are actual Office documents and can be read back with Unicode and numeric cells', async (t) => {
  const root = await scratch(t);
  const signal = new AbortController().signal;
  const result = await createDeliverables([
    { name: '修改后的合同.docx', content: '# 合同草案\n预算 24680 元\n交付日期：2026 年 12 月。\nA < B & C' },
    { name: '汇总.xlsx', sheets: [{ name: '经营数据', rows: [['名称', '金额', '确认'], ['收入', 24680, true], ['公式文本', '=2+2', null]] }] },
    { name: '结果.json', content: '{"合计":24680}' },
  ], root, signal);
  assert.equal(result.files.length, 3);
  const snapshot = await readAttachments(result.files.map((file) => file.path), join(root, 'reparse'), signal);
  assert.equal(snapshot.attachments.filter((item) => item.status === 'parsed').length, 3);
  const contents = Object.values(snapshot.files).map((file) => file.content).join('\n');
  assert.match(contents, /预算 24680 元/);
  assert.match(contents, /A < B & C/);
  assert.match(contents, /B2=24680/);
  assert.match(contents, /B3==2\+2/);
  assert.ok(!contents.includes('[缓存值：'));
});

test('invalid batches, traversal, duplicate names and invalid worksheets publish no files', async (t) => {
  const root = await scratch(t);
  const signal = new AbortController().signal;
  for (const specs of [
    [{ name: '../original.txt', content: 'overwrite' }],
    [{ name: 'good.txt', content: 'valid' }, { name: 'BAD.exe', content: 'invalid' }],
    [{ name: 'a.txt', content: 'one' }, { name: 'A.txt', content: 'two' }],
    [{ name: 'data.json', content: 'not JSON' }],
    [{ name: 'data.xlsx', sheets: [{ name: 'data', rows: [[{ formula: 'NOW()' }]] }] }],
    [{ name: 'data.xlsx', sheets: [{ name: 'bad/name', rows: [[1]] }] }],
  ]) await assert.rejects(createDeliverables(specs, root, signal));
  assert.deepEqual(await readdir(root), []);
  const controller = new AbortController(); controller.abort();
  await assert.rejects(createDeliverables([{ name: 'cancelled.txt', content: 'x' }], root, controller.signal), { name: 'AbortError' });
  assert.deepEqual(await readdir(root), []);
});

test('remote generation persists files, emits real creation traces, and makes actual output available to follow-up edits', async (t) => {
  const root = await scratch(t);
  const original = join(root, '原文.txt');
  await writeFile(original, '预算 100 元。');
  const events = [];
  const provider = { generate: async (instruction, payload) => {
    return { answer: '已把预算修改为 200 元。', files: [{ name: '修改版.txt', content: '预算 200 元。' }] };
  } };
  const run = new AgentRun({ question: '预算改为 200 元，生成新文件', sourceMode: 'files', selectedFiles: [original], mode: 'rwkv', outputMode: 'files' }, join(root, 'runs'), (event) => events.push(event), { provider });
  const state = await run.execute();
  assert.equal(state.status, 'completed');
  assert.equal(await readFile(original, 'utf8'), '预算 100 元。');
  assert.equal(await readFile(state.deliverables[0].path, 'utf8'), '预算 200 元。');
  assert.ok(events.some((event) => event.type === 'files.created'));
  assert.ok(state.traces.some((trace) => trace.name === 'files.create' && trace.status === 'completed'));
  const snapshot = JSON.parse(await readFile(join(run.directory, 'outputs.snapshot.json'), 'utf8'));
  assert.equal(snapshot.files['成果/修改版.txt'].content, '预算 200 元。');
  const followupProvider = { generate: async (instruction, payload) => {
      assert.ok(payload.sourceTexts.some((file) => file.excerpt.includes('预算 200 元')));
      return { answer: '已修改上一版。', files: [{ name: '修改版v2.txt', content: '预算 300 元。' }] };

  } };
  const next = new AgentRun({ question: '把上一版改为 300 元', sourceMode: 'files', selectedFiles: [original], reuseSnapshot: join(run.directory, 'outputs.snapshot.json'), mode: 'rwkv', outputMode: 'files' }, join(root, 'runs'), () => {}, { provider: followupProvider });
  const nextState = await next.execute();
  assert.equal(nextState.status, 'completed');
  assert.equal(await readFile(nextState.deliverables[0].path, 'utf8'), '预算 300 元。');
});

test('missing requested files never yields successful delivery; local mode explains that a model is needed', async (t) => {
  const root = await scratch(t);
  const provider = { generate: async (instruction, payload) => {
    return { answer: '已经生成文件。' };
  } };
  const command = { question: '生成文档', sourceMode: 'text', mode: 'rwkv', outputMode: 'files' };
  const state = await new AgentRun(command, root, () => {}, { provider }).execute();
  assert.equal(state.status, 'partial');
  assert.deepEqual(state.deliverables, []);
  assert.match(state.answer, /未生成成果文件/);
  const local = await new AgentRun({ ...command, mode: 'local' }, root, () => {}).execute();
  assert.equal(local.status, 'failed');
  assert.match(local.error, /需要模型.*在线 API 或本地模型/);
});
