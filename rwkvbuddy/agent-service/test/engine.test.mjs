import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, mkdir, writeFile, cp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { AgentRun, validateAnalysis, validateArtifact } from '../src/engine.mjs';
import { serviceRoot, runLua, Pool } from '../src/runtime.mjs';
import { scanWorkspace, financeSnapshot } from '../src/workspace.mjs';

async function scratch(t) {
  const path = await mkdtemp(join(tmpdir(), 'rwkvbuddy-test-'));
  t.after(async () => {
    // Verify the exact allocated directory before recursive Windows cleanup.
    assert.equal(dirname(resolve(path)), resolve(tmpdir()));
    assert.ok(path.split(/[\\/]/).at(-1).startsWith('rwkvbuddy-test-'));
    await rm(path, { recursive: true, force: true });
  });
  return path;
}
const question = '分析经营与资金情况，指出异常，给我报告';
const command = (mode = 'local') => ({ question, mode, workspace: join(serviceRoot, 'fixtures') });

test('real Windows Lua tools overlap; review consumes published versions; all money fields match', async (t) => {
  const root = await scratch(t);
  const events = [];
  const run = new AgentRun(command(), root, (event) => events.push(event));
  const state = await run.execute();
  assert.equal(state.status, 'completed');
  assert.equal(state.artifacts.length, 3);
  assert.equal(state.tasks.reviewer.status, 'verified');
  assert.deepEqual(new Set(state.review.inputArtifacts), new Set(['operations-v1', 'cash-v1', 'risk-v1']));
  for (const value of ['450,500.00', '341,250.00', '278,400.00', '56,900.25', '本地规则']) assert.ok(state.report.includes(value));
  assert.equal(await readFile(state.reportPath, 'utf8'), state.report);
  let active = 0; let peak = 0;
  for (const event of events) {
    if (event.type === 'tool.started' && event.payload.name === 'lua.verify') peak = Math.max(peak, ++active);
    if (event.type === 'tool.finished' && event.payload.name === 'lua.verify') active--;
  }
  assert.equal(peak, 2);
  const firstReview = events.findIndex((e) => e.type === 'review.completed');
  assert.equal(events.slice(0, firstReview).filter((e) => e.type === 'artifact.created').length, 3);
  assert.ok(events.every((e, i) => e.seq === i + 1));
});

test('missing cash input fails only cash expert and yields transparent partial report', async (t) => {
  const root = await scratch(t);
  const workspace = join(root, '资料 空格');
  await cp(join(serviceRoot, 'fixtures'), workspace, { recursive: true });
  const cashPath = join(workspace, 'jobs', 'group-cash', 'cash.jsonl');
  // Exact file deletion, no recursive cleanup of user input.
  await rm(cashPath);
  const state = await new AgentRun({ ...command(), workspace }, join(root, 'runs'), () => {}).execute();
  assert.equal(state.status, 'partial');
  assert.equal(state.tasks.cash.status, 'failed');
  assert.equal(state.tasks.operations.status, 'verified');
  assert.ok(state.report.includes('没有 cash.jsonl'));
  assert.equal(state.artifacts.some((a) => a.roleId === 'cash'), false);
});

test('RWKV experts are independent; reviewer requests one targeted revision and consumes v2', async (t) => {
  const root = await scratch(t);
  let reviews = 0;
  const provider = { generate: async (instruction, payload) => {
    if (instruction.startsWith('你是任务协调员')) return { answer: '已整合专家成果与复核结论 [E1]' };
    if (instruction.startsWith('你是质量复核员')) {
      return ++reviews === 1 ? { approved: false, summary: '经营结论需补充来源说明', issues: [{ taskId: 'operations', reason: '补充口径局限' }] }
        : { approved: true, summary: '修订后通过', issues: [] };
    }
    return { summary: instruction.includes('必须处理') ? '已修订' : '独立专家结论', findings: payload.verifiedFindings };
  } };
  const events = [];
  const state = await new AgentRun(command('rwkv'), root, (e) => events.push(e), { provider }).execute();
  assert.equal(state.status, 'completed');
  assert.equal(state.artifacts.length, 4);
  assert.equal(state.artifacts.filter((a) => a.roleId === 'cash').length, 1);
  assert.ok(state.review.inputArtifacts.includes('operations-v2'));
  assert.ok(!state.review.inputArtifacts.includes('operations-v1'));
  assert.equal(events.filter((e) => e.type === 'review.requested').length, 1);
  assert.equal(state.tasks.operations.attempt, 2);
});

test('failed model expert is not replaced by local results or marked successful', async (t) => {
  const root = await scratch(t);
  const provider = { generate: async (instruction, payload) => {
    if (instruction.startsWith('你是任务协调员')) return { answer: '可用成果已整合，经营分析失败。' };
    if (instruction.startsWith('你是质量复核员')) return { approved: true, summary: '已检查可用成果', issues: [] };
    if (instruction.includes('经营分析师')) throw new Error('injected network failure');
    return { summary: '有效成果', findings: payload.verifiedFindings };
  } };
  const state = await new AgentRun(command('rwkv'), root, () => {}, { provider }).execute();
  assert.equal(state.status, 'partial');
  assert.equal(state.tasks.operations.status, 'failed');
  assert.ok(!state.artifacts.some((a) => a.roleId === 'operations'));
  assert.ok(state.report.includes('injected network failure'));
});

test('failed requested revision never approves the superseded expert artifact', async (t) => {
  const root = await scratch(t);
  let reviews = 0;
  const provider = { generate: async (instruction, payload) => {
    if (instruction.startsWith('你是任务协调员')) return { answer: '存在未通过复核的成果。' };
    if (instruction.startsWith('你是质量复核员')) {
      reviews++;
      return { approved: false, summary: '需要补充经营口径', issues: [{ taskId: 'operations', reason: '补充来源说明' }] };
    }
    if (instruction.includes('必须处理')) throw new Error('revision connection failed');
    return { summary: '专家初稿', findings: payload.verifiedFindings };
  } };
  const state = await new AgentRun(command('rwkv'), root, () => {}, { provider }).execute();
  assert.equal(reviews, 1);
  assert.equal(state.status, 'partial');
  assert.equal(state.review.approved, false);
  assert.equal(state.tasks.operations.status, 'failed');
  assert.equal(state.tasks.reviewer.status, 'failed');
  assert.ok(state.artifacts.some((artifact) => artifact.id === 'operations-v1'));
  assert.ok(!state.artifacts.some((artifact) => artifact.id === 'operations-v2'));
  assert.ok(state.report.includes('未通过复核'));
  assert.ok(!state.report.includes('· 复核通过'));
});

test('cancellation aborts active and queued model work without publishing late artifacts', async (t) => {
  const root = await scratch(t);
  let requests = 0;
  let ready;
  const waiting = new Promise((done) => { ready = done; });
  const provider = { generate: (_instruction, _payload, signal) => new Promise((_resolve, reject) => {
    if (++requests === 3) ready();
    signal.addEventListener('abort', () => reject(new DOMException('cancelled', 'AbortError')), { once: true });
  }) };
  const run = new AgentRun(command('rwkv'), root, () => {}, { provider });
  const completion = run.execute();
  await waiting;
  run.cancel();
  const state = await completion;
  assert.equal(state.status, 'cancelled');
  assert.equal(state.artifacts.length, 0);
  assert.ok(['operations', 'cash', 'risk'].every((id) => state.tasks[id].status === 'cancelled'));
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

test('citations and input snapshot versions must match; malformed finance input is rejected', async (t) => {
  assert.throws(() => validateAnalysis({ summary: 'x', findings: [{ text: 'x', evidenceIds: ['invented'] }] }, [{ id: 'E1' }]));
  assert.throws(() => validateArtifact({ snapshotHash: 'old' }, 'new', []), /不同版本/);
  const root = await scratch(t);
  await mkdir(join(root, 'jobs', 'co-x'), { recursive: true });
  await mkdir(join(root, 'shared'));
  await writeFile(join(root, 'shared', 'tax_rates.tsv'), 'entity\tcit_rate\nx\t0.15\n');
  await writeFile(join(root, 'jobs', 'co-x', 'ledger.csv'), 'account,amount\nsales,10;os.execute(1)\n');
  const snapshot = await scanWorkspace(root);
  assert.throws(() => financeSnapshot(snapshot), /无效数字/);
});

test('document-only workspaces use distinct research/technical/risk roles', async (t) => {
  const root = await scratch(t);
  const workspace = join(root, '文档');
  await mkdir(workspace);
  await writeFile(join(workspace, 'README.md'), '# 产品计划\n这是一个本地桌面分析工具。\nTODO: 补充部署说明。');
  const state = await new AgentRun({ question: '研究这个目录', mode: 'local', workspace }, join(root, 'runs'), () => {}).execute();
  assert.equal(state.status, 'completed');
  assert.equal(state.roles.find((r) => r.id === 'operations').name, '资料研究员');
  assert.ok(state.report.includes('TODO'));
});

test('expert consumes real tool results; model/tool traces persist outcomes and synthesis failure is partial', async (t) => {
  const root = await scratch(t);
  const file = join(root, '客户需求.txt');
  await writeFile(file, '预算 24680 元\n合同尚未签署');
  const seen = new Set();
  let contextObserved = false;
  const provider = { generate: async (instruction, payload) => {
    if (instruction.startsWith('你是质量复核员')) return { approved: true, summary: '来源匹配', issues: [] };
    if (instruction.startsWith('你是任务协调员')) throw new Error('synthesis failed');
    contextObserved ||= payload.previousTurn?.question === '上轮问题';
    if (instruction.includes('资料分析师') && !seen.has('read')) {
      seen.add('read'); return { tool: 'read_file', arguments: { evidenceId: payload.evidence[0].id, startLine: 1, lineCount: 2 } };
    }
    if (instruction.includes('资料分析师')) assert.match(payload.toolResults[0].result.text, /24680/);
    return { summary: '已读取资料', findings: payload.verifiedFindings };
  } };
  const events = [];
  const run = new AgentRun({ question: '指出风险', sourceMode: 'files', selectedFiles: [file], workspace: '', mode: 'rwkv',
    context: { question: '上轮问题', report: '上轮结论' }, config: { apiKey: 'private-token' } }, join(root, 'runs'), (event) => events.push(event), { provider });
  const state = await run.execute();
  assert.ok(contextObserved);
  assert.equal(state.status, 'partial');
  assert.match(state.report, /状态：部分完成/);
  assert.match(state.answer, /synthesis failed/);
  const read = state.traces.find((item) => item.name === 'read_file');
  assert.equal(read.status, 'completed');
  assert.match(read.output, /24680/);
  assert.ok(read.durationMs >= 0 && read.finishedAt);
  assert.equal(state.traces.find((item) => item.roleId === 'coordinator' && item.kind === 'model').status, 'failed');
  assert.equal(events.find((item) => item.type === 'trace.started' && item.payload.trace.id === read.id).payload.trace.status, 'running');
  const saved = await readFile(join(run.directory, 'run.json'), 'utf8');
  assert.ok(!saved.includes('private-token'));
  assert.deepEqual(JSON.parse(saved).traces, state.traces);
});
