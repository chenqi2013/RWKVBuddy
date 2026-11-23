import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createDeliverables } from '../src/deliverables.mjs';
import { readAttachments } from '../src/attachments.mjs';
import { AgentRun } from '../src/engine.mjs';
import ExcelJS from 'exceljs';

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

test('automatic file generation persists outputs and makes them available to follow-up edits without a file switch', async (t) => {
  const root = await scratch(t);
  const original = join(root, '原文.txt');
  await writeFile(original, '预算 100 元。');
  const events = [];
  const provider = { generate: async (instruction, payload) => {
    return { answer: '已把预算修改为 200 元。', files: [{ name: '修改版.txt', content: '预算 200 元。' }] };
  } };
  const run = new AgentRun({ question: '预算改为 200 元，生成新文件', sourceMode: 'files', selectedFiles: [original], mode: 'rwkv', outputMode: 'auto' }, join(root, 'runs'), (event) => events.push(event), { provider });
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
  const next = new AgentRun({ question: '把上一版改为 300 元', sourceMode: 'files', selectedFiles: [original], reuseSnapshot: join(run.directory, 'outputs.snapshot.json'), mode: 'rwkv', outputMode: 'auto' }, join(root, 'runs'), () => {}, { provider: followupProvider });
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

test('invalid RWKV Excel content is sent back for repair and creates a real workbook with preserved failure traces', async (t) => {
  const root = await scratch(t);
  const rejected = [{ name: '财务汇总.xlsx', content: '| 公司 | 金额 |\n|---|---|\n| 示例 | 123 |' }];
  let calls = 0;
  const events = [];
  const provider = { generate: async (instruction, payload) => {
    calls++;
    if (calls === 1) return { answer: '无法直接提供下载，请自己保存。', files: rejected };
    assert.match(instruction, /本轮文件生成工具已拒绝提交/);
    assert.equal(payload.previousTurn, undefined);
    assert.match(payload.deliveryFeedback.error, /财务汇总.xlsx.*sheets/);
    assert.deepEqual(payload.deliveryFeedback.rejectedFiles, rejected);
    assert.equal(payload.question, '以.xlsx格式保存');
    return { answer: '已提交工作表，生成财务汇总文件。', files: [{ name: '财务汇总.xlsx', sheets: [{ name: '汇总', rows: [['公司', '金额'], ['示例', 123]] }] }] };
  } };
  const run = new AgentRun({ question: '以.xlsx格式保存', mode: 'rwkv', sourceMode: 'text' }, root, event => events.push(event), { provider });
  const state = await run.execute();
  assert.equal(state.status, 'completed', state.error);
  assert.equal(calls, 2);
  assert.equal(state.deliverables.length, 1);
  assert.ok(!state.answer.includes('自己保存'));
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.readFile(state.deliverables[0].path);
  assert.equal(workbook.worksheets.length, 1);
  assert.equal(workbook.worksheets[0].getCell('B2').value, 123);
  const traces = state.traces.filter(trace => trace.name === 'files.create');
  assert.deepEqual(traces.map(trace => trace.status), ['failed', 'completed']);
  assert.deepEqual(traces[0].input.files, rejected);
  assert.equal(events.filter(event => event.type === 'files.recovering').length, 1);
  assert.equal(events.filter(event => event.type === 'files.created').length, 1);
});

test('file structure recovery is bounded and never publishes a workbook with repeated invalid sheets', async (t) => {
  const root = await scratch(t);
  let calls = 0;
  const provider = { generate: async () => {
    calls++;
    return { answer: '已生成工作簿。', files: [{ name: '汇总.xlsx', content: '普通文字不是工作表' }] };
  } };
  const run = new AgentRun({ question: '生成汇总.xlsx', mode: 'rwkv', sourceMode: 'text' }, root, () => {}, { provider });
  const state = await run.execute();
  assert.equal(state.status, 'partial');
  assert.equal(calls, 3);
  assert.match(state.error, /工作簿需要 1–8 个工作表.*sheets/);
  assert.deepEqual(state.deliverables, []);
  assert.equal(state.traces.filter(trace => trace.name === 'files.create' && trace.status === 'failed').length, 3);
  assert.ok(!(await readdir(run.directory)).includes('outputs'));
});

test('a file-only model response receives format feedback rather than losing its requested workbook', async (t) => {
  const root = await scratch(t);
  let calls = 0;
  const provider = { generate: async (_instruction, payload) => {
    if (++calls === 1) return { progress: '整理 Excel', files: [{ name: '结果.xlsx', content: '项目,金额\n示例,123' }] };
    assert.match(payload.deliveryFeedback.error, /answer.*sheets/);
    return { answer: '已提交 Excel 数据。', files: [{ name: '结果.xlsx', sheets: [{ name: '数据', rows: [['项目', '金额'], ['示例', 123]] }] }] };
  } };
  const state = await new AgentRun({ question: '生成结果.xlsx', mode: 'rwkv', sourceMode: 'text' }, root, () => {}, { provider }).execute();
  assert.equal(state.status, 'completed', state.error);
  assert.equal(state.deliverables[0].name, '结果.xlsx');
  assert.equal(calls, 2);
});

test('empty repair responses and filesystem errors do not masquerade as successful file delivery', async (t) => {
  const root = await scratch(t);
  let calls = 0;
  const provider = { generate: async () => ++calls === 1
    ? { answer: '生成文件。', files: [{ name: '数据.xlsx', sheets: [] }] }
    : { answer: '已生成。', files: [] } };
  const state = await new AgentRun({ question: '生成数据.xlsx', mode: 'rwkv', sourceMode: 'text' }, root, () => {}, { provider }).execute();
  assert.equal(state.status, 'partial');
  assert.match(state.error, /修正响应未提交有效回答和文件/);
  assert.deepEqual(state.deliverables, []);
  const blocked = join(root, 'blocked');
  await writeFile(blocked, '文件而非目录');
  await assert.rejects(createDeliverables([{ name: '合法.xlsx', sheets: [{ name: '汇总', rows: [[1]] }] }], blocked, new AbortController().signal),
    error => error.code !== 'DELIVERY_INVALID_SPEC');
});
