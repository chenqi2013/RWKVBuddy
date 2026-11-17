import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, mkdir, writeFile, cp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { AgentRun } from '../src/engine.mjs';
import { serviceRoot, runLua, Pool } from '../src/runtime.mjs';
import { scanWorkspace, financeSnapshot } from '../src/workspace.mjs';

async function scratch(t) {
  const path = await mkdtemp(join(tmpdir(), 'rwkvbuddy-test-'));
  t.after(async () => {
    assert.equal(dirname(resolve(path)), resolve(tmpdir()));
    assert.ok(path.split(/[\\/]/).at(-1).startsWith('rwkvbuddy-test-'));
    await rm(path, { recursive: true, force: true });
  });
  return path;
}
const command = (mode = 'local') => ({ question: '分析经营与资金情况，指出异常，给我报告', mode, workspace: join(serviceRoot, 'fixtures') });

test('single local flow persists real reads, Lua calculations and results without synthetic role steps', async (t) => {
  const root = await scratch(t);
  const events = [];
  const state = await new AgentRun(command(), root, (event) => events.push(event)).execute();
  assert.equal(state.status, 'completed');
  assert.deepEqual(state.roles, []);
  assert.deepEqual(state.artifacts, []);
  assert.deepEqual(state.traces.map((trace) => trace.name), ['input.read', 'lua.ledger', 'lua.cash', 'local.analyze']);
  assert.ok(state.traces.every((trace) => trace.status === 'completed'));
  for (const value of ['450,500.00', '341,250.00', '278,400.00', '56,900.25']) assert.ok(state.report.includes(value));
  assert.ok(!state.report.includes('复核通过'));
  assert.equal(await readFile(state.reportPath, 'utf8'), state.report);
  assert.ok(events.every((event, index) => event.seq === index + 1));
});

test('missing cash input yields available calculations with an explicit partial result', async (t) => {
  const root = await scratch(t);
  const workspace = join(root, '资料 空格');
  await cp(join(serviceRoot, 'fixtures'), workspace, { recursive: true });
  await rm(join(workspace, 'jobs', 'group-cash', 'cash.jsonl'));
  const state = await new AgentRun({ ...command(), workspace }, join(root, 'runs'), () => {}).execute();
  assert.equal(state.status, 'partial');
  assert.ok(state.traces.some((trace) => trace.name === 'lua.ledger'));
  assert.ok(!state.traces.some((trace) => trace.name === 'lua.cash'));
  assert.match(state.report, /无法完成资金核算/);
});

test('model reads actual file content, recovers from a failed calculation, and receives previous context', async (t) => {
  const root = await scratch(t);
  const file = join(root, '客户需求.txt');
  await writeFile(file, '预算 24680 元\n合同尚未签署');
  let calls = 0;
  const provider = { generate: async (instruction, payload) => {
    assert.ok(instruction.startsWith('你是文件处理助手'));
    assert.equal(payload.previousTurn.question, '上轮问题');
    calls++;
    if (calls === 1) return { tool: 'read_file', arguments: { evidenceId: payload.evidence[0].id, startLine: 1, lineCount: 2 } };
    assert.match(payload.toolResults[0].result.text, /24680/);
    if (calls === 2) return { tool: 'calculator', arguments: { expression: '1/0' } };
    assert.match(payload.toolResults[1].result.error, /溢出/);
    if (calls === 3) return { tool: 'calculator', arguments: { expression: '24680*2' } };
    assert.equal(payload.toolResults[2].result.result, 49360);
    return { answer: '两份预算为 49360 元，合同尚未签署 [E1]。' };
  } };
  const events = [];
  const run = new AgentRun({ question: '两份预算合计多少？', sourceMode: 'files', selectedFiles: [file], mode: 'rwkv',
    context: { question: '上轮问题' }, config: { apiKey: 'private-token' } }, join(root, 'runs'), (event) => events.push(event), { provider });
  const state = await run.execute();
  assert.equal(state.status, 'completed');
  assert.equal(calls, 4);
  assert.match(state.answer, /49360/);
  assert.ok(events.some((event) => event.type === 'input.file_parsed' && event.payload.lines === 2));
  const read = state.traces.find((trace) => trace.name === 'read_file');
  assert.match(read.output, /24680/);
  assert.equal(read.context.path, state.evidence[0].path);
  assert.equal(state.traces.find((trace) => trace.name === 'calculator').status, 'failed');
  assert.equal(events.find((event) => event.type === 'trace.started' && event.payload.trace.id === read.id).payload.trace.status, 'running');
  const saved = await readFile(join(run.directory, 'run.json'), 'utf8');
  assert.ok(!saved.includes('private-token'));
  assert.deepEqual(JSON.parse(saved).traces, state.traces);
});

test('failed model request remains failed without replacing its answer with local analysis', async (t) => {
  const root = await scratch(t);
  const provider = { generate: async () => { throw new Error('injected network failure'); } };
  const state = await new AgentRun({ question: '写一份方案', sourceMode: 'text', mode: 'rwkv' }, root, () => {}, { provider }).execute();
  assert.equal(state.status, 'failed');
  assert.equal(state.answer, '');
  assert.match(state.error, /injected network failure/);
  assert.equal(state.traces.at(-1).status, 'failed');
});

test('live public model progress is forwarded and kept in completed history', async (t) => {
  const root = await scratch(t);
  const events = [];
  const provider = { generate: async (_instruction, _payload, _signal, delta) => {
    delta(0, '', { phase: 'requesting' });
    const text = '{"progress":"整理当前问题","answer":"正文草稿';
    delta(text.length, text, { phase: 'streaming' });
    assert.ok(events.some((event) => event.type === 'trace.delta' && event.payload.answerPreview === '正文草稿'));
    return { progress: '整理当前问题', answer: '正文草稿完成' };
  } };
  const run = new AgentRun({ question: '写方案', sourceMode: 'text', mode: 'rwkv' }, root, (event) => events.push(event), { provider });
  const state = await run.execute();
  assert.equal(state.status, 'completed');
  assert.equal(state.traces.at(-1).progress, '整理当前问题');
  assert.equal(state.traces.at(-1).answerPreview, '正文草稿完成');
  const saved = JSON.parse(await readFile(join(run.directory, 'run.json'), 'utf8'));
  assert.equal(saved.traces.at(-1).progress, '整理当前问题');
});

test('tool call limit terminates a repeated model loop without claiming completion', async (t) => {
  const root = await scratch(t);
  let calls = 0;
  const provider = { generate: async () => { calls++; return { tool: 'calculator', arguments: { expression: '6*7' } }; } };
  const state = await new AgentRun({ question: '计算', sourceMode: 'text', mode: 'rwkv' }, root, () => {}, { provider }).execute();
  assert.equal(state.status, 'failed');
  assert.equal(calls, 7);
  assert.equal(state.traces.filter((trace) => trace.name === 'calculator').length, 6);
  assert.match(state.error, /调用上限/);
});

test('cancellation aborts active model work and persists a cancelled step', async (t) => {
  const root = await scratch(t);
  let ready;
  const waiting = new Promise((done) => { ready = done; });
  const provider = { generate: (_instruction, _payload, signal) => new Promise((_resolve, reject) => {
    signal.addEventListener('abort', () => reject(new DOMException('cancelled', 'AbortError')), { once: true });
    ready();
  }) };
  const run = new AgentRun({ question: '分析', sourceMode: 'text', mode: 'rwkv' }, root, () => {}, { provider });
  const completion = run.execute();
  await waiting;
  run.cancel();
  const state = await completion;
  assert.equal(state.status, 'cancelled');
  assert.deepEqual(state.deliverables, []);
  assert.equal(state.traces.at(-1).status, 'cancelled');
});

test('Lua cancellation terminates a running process and releases pool resource', async () => {
  const controller = new AbortController();
  const pool = new Pool(1);
  const operation = pool.use(() => runLua('while true do end', { signal: controller.signal,
    onStart: () => controller.abort() }), controller.signal);
  await assert.rejects(operation, { name: 'AbortError' });
  assert.equal(pool.active, 0);
});

test('cancelled queue entry never executes; concurrent model pool honors configured maximum', async () => {
  const pool = new Pool(2);
  let live = 0; let peak = 0;
  await Promise.all(Array.from({ length: 7 }, () => pool.use(async () => {
    peak = Math.max(peak, ++live);
    await new Promise((done) => setTimeout(done, 10)); live--;
  })));
  assert.equal(peak, 2);
  const single = new Pool(1);
  let release;
  const held = single.use(() => new Promise((done) => { release = done; }));
  await new Promise((done) => setImmediate(done));
  const controller = new AbortController();
  const queued = single.use(() => assert.fail('cancelled queue executed'), controller.signal);
  controller.abort();
  await assert.rejects(queued, { name: 'AbortError' });
  release(); await held;
});

test('malformed finance input is rejected before running Lua', async (t) => {
  const root = await scratch(t);
  await mkdir(join(root, 'jobs', 'co-x'), { recursive: true });
  await mkdir(join(root, 'shared'));
  await writeFile(join(root, 'shared', 'tax_rates.tsv'), 'entity\tcit_rate\nx\t0.15\n');
  await writeFile(join(root, 'jobs', 'co-x', 'ledger.csv'), 'account,amount\nsales,10;os.execute(1)\n');
  const snapshot = await scanWorkspace(root);
  assert.throws(() => financeSnapshot(snapshot), /无效数字/);
});

test('document-only workspace produces direct local results without fixed expert roles', async (t) => {
  const root = await scratch(t);
  const workspace = join(root, '文档');
  await mkdir(workspace);
  await writeFile(join(workspace, 'README.md'), '# 产品计划\n这是一个本地桌面分析工具。\nTODO: 补充部署说明。');
  const state = await new AgentRun({ question: '研究这个目录', mode: 'local', workspace }, join(root, 'runs'), () => {}).execute();
  assert.equal(state.status, 'completed');
  assert.deepEqual(state.roles, []);
  assert.match(state.report, /TODO/);
});

test('token truncation retries with compact output while preserving the failed request record', async (t) => {
  const root = await scratch(t);
  let calls = 0;
  const provider = { generate: async (instruction) => {
    if (++calls === 1) throw Object.assign(new Error('输出被截断'), { code: 'MODEL_OUTPUT_TRUNCATED' });
    assert.match(instruction, /800 字/);
    return { answer: '工程功能和技术栈概述。' };
  } };
  const state = await new AgentRun({ question: '介绍工程', sourceMode: 'text', mode: 'rwkv' }, root, () => {}, { provider }).execute();
  assert.equal(state.status, 'completed', state.error);
  assert.equal(calls, 2);
  assert.deepEqual(state.traces.filter((trace) => trace.kind === 'model').map((trace) => trace.status), ['failed', 'completed']);
  calls = 0;
  const broken = { generate: async () => { calls++; throw Object.assign(new Error('输出被截断'), { code: 'MODEL_OUTPUT_TRUNCATED' }); } };
  const failed = await new AgentRun({ question: '介绍工程', sourceMode: 'text', mode: 'rwkv' }, root, () => {}, { provider: broken }).execute();
  assert.equal(failed.status, 'failed');
  assert.equal(calls, 3);
});

test('truncated file delivery increases output allowance and retries compact files without publishing fragments', async (t) => {
  const root = await scratch(t);
  let calls = 0;
  const events = [];
  const provider = { generate: async (instruction, _payload, _signal, delta, options) => {
    calls++;
    if (calls < 3) {
      if (calls === 2) {
        assert.equal(options.maxTokens, 8192);
        assert.match(instruction, /精简报告/);
      }
      const text = '{"progress":"整理表格","answer":"未完成草稿';
      delta(text.length, text, { phase: 'streaming' });
      throw Object.assign(new Error('输出被截断'), { code: 'MODEL_OUTPUT_TRUNCATED' });
    }
    assert.equal(options.maxTokens, 8192);
    assert.match(instruction, /200 字/);
    assert.equal(events.some((event) => event.type === 'files.created'), false);
    return { answer: '关键结论已整理。', files: [{ name: '报告.md', content: '# 汇总\n实际结果。' }] };
  } };
  const state = await new AgentRun({ question: '分析表格并生成文件', sourceMode: 'text', mode: 'rwkv', outputMode: 'files', config: { maxTokens: 4096 } }, root, (event) => events.push(event), { provider }).execute();
  assert.equal(state.status, 'completed', state.error);
  assert.equal(calls, 3);
  assert.equal(state.deliverables.length, 1);
  assert.equal(events.filter((event) => event.type === 'model.recovering').length, 2);
  assert.equal(state.traces.filter((trace) => trace.kind === 'model').at(-1).answerPreview, state.answer);
});
