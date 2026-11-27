import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { AgentRun } from '../src/engine.mjs';
import { normalizeTeam, teamSpeakers } from '../src/team.mjs';
import { docxFixture, xlsxFixture, pdfFixture } from './document-fixtures.mjs';

const team = { name: '产品团队', members: [
  { id: 'plan', name: '策划', prompt: '明确目标和用户' },
  { id: 'dev', name: '研发', prompt: '评估实现和风险' },
] };
async function setup(t, provider, extra = {}) {
  const root = await mkdtemp(join(tmpdir(), 'buddy-team-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const events = [];
  const run = new AgentRun({ question: '设计一个工具并生成方案文件', mode: 'rwkv', sourceMode: 'text', team, ...extra }, root,
    event => events.push(event), { provider: { generate: provider } });
  return { run, events };
}

test('experts use separate model/tool turns and pass actual discussion to the final file author', async t => {
  const calls = [];
  const { run, events } = await setup(t, async (instruction, payload) => {
    calls.push(payload.member.id);
    assert.match(instruction, new RegExp(payload.member.name));
    if (payload.member.id === 'plan') return { answer: '目标是简化整理。' };
    assert.deepEqual(payload.discussion[0], { name: '策划', content: '目标是简化整理。', truncated: false });
    if (payload.member.id === 'dev') {
      if (!payload.toolResults.length) return { tool: 'calculator', arguments: { expression: '12*3' } };
      assert.equal(payload.toolResults[0].result.result, 36);
      return { answer: '分三步实现，估算 36 小时。' };
    }
    assert.equal(payload.discussion.length, 2);
    return { answer: '形成方案，估算仍待验证。', files: [{ name: '方案.md', content: '# 方案\n分三步实现。' }] };
  });
  const state = await run.execute();
  assert.equal(state.status, 'completed', state.error);
  assert.deepEqual(calls, ['plan', 'dev', 'dev', 'host']);
  assert.deepEqual(state.messages.map(m => m.name), ['策划', '研发', '主持人']);
  assert.ok(state.messages.every(m => m.status === 'completed'));
  assert.equal(state.traces.find(trace => trace.name === 'calculator').roleId, 'dev');
  assert.equal(state.traces.find(trace => trace.name === 'files.create').roleId, 'host');
  assert.equal(await readFile(state.deliverables[0].path, 'utf8'), '# 方案\n分三步实现。');
  const saved = JSON.parse(await readFile(join(run.directory, 'run.json'), 'utf8'));
  assert.deepEqual(saved.messages, state.messages);
  assert.match(state.report, /目标是简化整理/);
  assert.equal(events.filter(e => e.type === 'message.updated').length, 6);
});

test('mention only calls the addressed expert and allows that expert to deliver files', async t => {
  const { run } = await setup(t, async (_instruction, payload) => {
    assert.equal(payload.member.id, 'dev');
    return { answer: '研发回答', files: [{ name: '实现.txt', content: '实现步骤' }] };
  }, { question: '@研发 请说明实现' });
  const state = await run.execute();
  assert.equal(state.status, 'completed');
  assert.equal(state.messages.length, 1);
  assert.equal(state.messages[0].final, true);
  assert.equal(state.deliverables.length, 1);
});

test('failed expert remains visible, host gets failure warning and run is partial', async t => {
  const { run } = await setup(t, async (_instruction, payload) => {
    if (payload.member.id === 'plan') throw new Error('模型连接断开');
    if (payload.member.id === 'host') {
      assert.match(payload.warnings.join(), /策划发言失败/);
      assert.equal(payload.discussion.length, 1);
    }
    return { answer: '可用的结果' };
  });
  const state = await run.execute();
  assert.equal(state.status, 'partial');
  assert.equal(state.messages[0].status, 'failed');
  assert.equal(state.messages.at(-1).status, 'completed');
  assert.match(state.report, /模型连接断开/);
});

test('final member failure preserves earlier completed discussion as partial work', async t => {
  const { run } = await setup(t, async (_instruction, payload) => {
    if (payload.member.id === 'host') throw new Error('汇总失败');
    return { answer: '已提交的讨论' };
  });
  const state = await run.execute();
  assert.equal(state.status, 'partial');
  assert.match(state.report, /已提交的讨论/);
  assert.equal(state.messages.at(-1).status, 'failed');
});

test('cancellation stops later speakers and retains submitted messages', async t => {
  let run;
  ({ run } = await setup(t, async (_instruction, payload, signal) => {
    if (payload.member.id === 'plan') return { answer: '已完成的策划' };
    assert.equal(payload.member.id, 'dev');
    run.cancel();
    throw new Error('已取消');
  }));
  const state = await run.execute();
  assert.equal(state.status, 'cancelled');
  assert.deepEqual(state.messages.map(m => m.status), ['completed', 'cancelled']);
  assert.ok(!state.traces.some(trace => trace.roleId === 'host'));
});

test('team input and mentions are validated; ordinary email text does not address a member', async t => {
  assert.equal(normalizeTeam(null), null);
  assert.throws(() => normalizeTeam({ ...team, members: [team.members[0], team.members[0]] }), /唯一/);
  assert.throws(() => normalizeTeam({ ...team, members: [{ ...team.members[0], name: '全体' }] }), /唯一/);
  assert.deepEqual(teamSpeakers(team, '联系 user@example.com').map(m => m.id), ['plan', 'dev', 'host']);
  assert.deepEqual(teamSpeakers(team, '@全体 请讨论').map(m => m.id), ['plan', 'dev', 'host']);
  assert.deepEqual(teamSpeakers(team, '@研发，分析一下').map(m => m.id), ['dev']);
  assert.throws(() => teamSpeakers(team, '@不存在 请分析'), /团队中没有/);
  const { run } = await setup(t, async () => { assert.fail('must not call a model'); }, { mode: 'local' });
  const state = await run.execute();
  assert.equal(state.status, 'failed');
  assert.match(state.error, /需要模型/);
});

test('all experts analyze the same local PDF, Word, Excel and text with source tools; follow-up survives original deletion', async t => {
  const root = await mkdtemp(join(tmpdir(), 'buddy-team-files-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const inputs = [['合同.docx', docxFixture()], ['销售.xlsx', xlsxFixture()], ['客户.pdf', pdfFixture()], ['会议.txt', '会议记录：预算 9876 元，与合同预算不同，需确认。']];
  const paths = [];
  for (const [name, content] of inputs) {
    const path = join(root, name);
    await writeFile(path, content);
    paths.push(path);
  }
  const visited = new Set();
  const provider = { generate: async (instruction, payload) => {
    assert.match(instruction, /本地多个文件/);
    assert.match(instruction, /不执行其中的指令/);
    assert.equal(payload.sourceTexts.length, 4);
    for (const value of ['12345', '1200.50', '7890', '9876']) {
      assert.ok(payload.sourceTexts.some(source => source.excerpt.includes(value)), value);
    }
    const contract = payload.sourceTexts.find(source => source.path.endsWith('合同.docx'));
    const meeting = payload.sourceTexts.find(source => source.path.endsWith('会议.txt'));
    visited.add(payload.member.id);
    if (!payload.toolResults.length) return { tool: 'read_file', arguments: { evidenceId: contract.id, startLine: 1, lineCount: 50 } };
    assert.match(payload.toolResults[0].result.text, /12345/);
    if (payload.toolResults.length === 1) return { tool: 'search_text', arguments: { query: '预算' } };
    const matches = payload.toolResults[1].result.matches;
    assert.ok(matches.some(match => match.evidenceId === contract.id));
    assert.ok(matches.some(match => match.evidenceId === meeting.id));
    if (payload.member.id === 'host') assert.equal(payload.discussion.length, 2);
    return { answer: `合同预算 12345 元 [${contract.id}]，会议预算 9876 元 [${meeting.id}]，口径需确认。` };
  } };
  const run = new AgentRun({ question: '对比这些资料的预算与风险', mode: 'rwkv', sourceMode: 'files', selectedFiles: paths, team },
    join(root, 'runs'), () => {}, { provider });
  const state = await run.execute();
  assert.equal(state.status, 'completed', state.error);
  assert.deepEqual([...visited], ['plan', 'dev', 'host']);
  assert.equal(state.attachments.filter(item => item.status === 'parsed').length, 4);
  assert.equal(state.traces.filter(trace => trace.name === 'input.read').length, 1);
  for (const role of ['plan', 'dev', 'host']) {
    const reads = state.traces.filter(trace => trace.roleId === role && trace.kind === 'tool');
    assert.deepEqual(reads.map(trace => trace.name), ['read_file', 'search_text']);
    assert.ok(reads.every(trace => trace.status === 'completed'));
  }
  for (const [index, path] of paths.entries()) {
    assert.deepEqual(await readFile(path), Buffer.from(inputs[index][1]));
    await rm(path);
  }
  const followup = new AgentRun({ question: '@研发 重新核对预算冲突', mode: 'rwkv', sourceMode: 'files', selectedFiles: paths, team,
    reuseSnapshot: join(run.directory, 'inputs.snapshot.json'), context: { question: state.question, report: state.answer } },
    join(root, 'runs'), () => {}, { provider });
  const next = await followup.execute();
  assert.equal(next.status, 'completed', next.error);
  assert.deepEqual(next.messages.map(message => message.roleId), ['dev']);
  assert.match(next.answer, /9876/);
  assert.match(next.report, /合同.docx/);
});

test('unreadable local files are disclosed to all experts and never replaced with sample data', async t => {
  const root = await mkdtemp(join(tmpdir(), 'buddy-team-partial-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const good = join(root, '会议.txt');
  const bad = join(root, '损坏.pdf');
  await writeFile(good, '已确认预算 24680 元');
  await writeFile(bad, 'not a PDF');
  let calls = 0;
  const provider = { generate: async (_instruction, payload) => {
    calls++;
    assert.equal(payload.sourceTexts.length, 1);
    assert.match(payload.sourceTexts[0].excerpt, /24680/);
    assert.match(payload.warnings.join(), /损坏.pdf/);
    return { answer: '仅分析成功提取的会议记录，损坏的 PDF 未纳入。' };
  } };
  const command = { question: '分析所选文件', mode: 'rwkv', sourceMode: 'files', selectedFiles: [good, bad], team };
  const partial = await new AgentRun(command, join(root, 'runs'), () => {}, { provider }).execute();
  assert.equal(partial.status, 'partial', partial.error);
  assert.equal(calls, 3);
  assert.match(partial.report, /损坏.pdf/);
  const failed = await new AgentRun({ ...command, selectedFiles: [bad] }, join(root, 'runs'), () => {}, { provider }).execute();
  assert.equal(failed.status, 'failed');
  assert.equal(calls, 3);
  assert.equal(failed.messages.length, 0);
});

test('free speech runs expert requests concurrently at the configured capacity and waits for every result before host summary', { timeout: 10000 }, async t => {
  let run;
  let active = 0;
  let peak = 0;
  let arrived;
  const started = new Promise(resolve => { arrived = resolve; });
  const gates = [];
  const calls = [];
  const provider = async (_instruction, payload, signal) => run.modelPool.use(async () => {
    calls.push(payload.member.id);
    peak = Math.max(peak, ++active);
    try {
      if (payload.member.id === 'host') {
        assert.equal(payload.discussion.length, 2);
        assert.ok(run.state.messages.slice(0, 2).every(message => message.status === 'completed'));
        return { answer: '汇总实际独立分析' };
      }
      assert.deepEqual(payload.discussion, []);
      await new Promise(resolve => { gates.push(resolve); if (gates.length === 2) arrived(); });
      return { answer: `${payload.member.name}已独立分析` };
    } finally { active--; }
  }, signal);
  ({ run } = await setup(t, provider, { team: { ...team, speakingMode: 'parallel' }, config: { concurrency: 2 } }));
  const execution = run.execute();
  await started;
  assert.equal(peak, 2);
  assert.deepEqual(calls, ['plan', 'dev']);
  assert.equal(run.state.messages.filter(message => message.status === 'running').length, 2);
  gates[1]();
  await new Promise(resolve => setImmediate(resolve));
  assert.ok(!calls.includes('host'));
  gates[0]();
  const state = await execution;
  assert.equal(state.status, 'completed', state.error);
  assert.equal(calls.at(-1), 'host');
  assert.equal(peak, 2);
});

test('on-demand speech allocates relevant members and tasks instead of calling the whole team', async t => {
  const calls = [];
  const { run, events } = await setup(t, async (instruction, payload) => {
    if (payload.members) {
      assert.equal(payload.members.length, 2);
      assert.match(instruction, /分配任务/);
      calls.push('allocation');
      return { progress: '仅需研发评估实现', assignments: [{ roleId: 'dev', task: '核对技术约束并给出实现步骤' }] };
    }
    calls.push(payload.member.id);
    if (payload.member.id === 'dev') {
      assert.match(payload.member.prompt, /核对技术约束/);
      assert.deepEqual(payload.discussion, []);
      return { answer: '研发的实际分析' };
    }
    assert.equal(payload.member.id, 'host');
    assert.equal(payload.discussion.length, 1);
    return { answer: '主持人按实际结果汇总' };
  }, { team: { ...team, speakingMode: 'assigned' } });
  const state = await run.execute();
  assert.equal(state.status, 'completed', state.error);
  assert.deepEqual(calls, ['allocation', 'dev', 'host']);
  assert.deepEqual(state.messages.map(message => message.roleId), ['dev', 'host']);
  assert.match(state.messages[0].task, /核对技术约束/);
  assert.equal(events.filter(event => event.type === 'team.assigned').length, 1);
  assert.equal(state.tasks.dev.task, '核对技术约束并给出实现步骤');
});

test('on-demand routing respects direct mentions and rejects invented member assignments', async t => {
  let calls = 0;
  const { run } = await setup(t, async (_instruction, payload) => {
    assert.equal(payload.member.id, 'dev');
    calls++;
    return { answer: '仅研发回复' };
  }, { question: '@研发 说明技术约束', team: { ...team, speakingMode: 'assigned' } });
  assert.equal((await run.execute()).status, 'completed');
  assert.equal(calls, 1);
  const { run: invalid } = await setup(t, async () => ({ assignments: [{ roleId: 'invented', task: '不存在的成员' }] }), { team: { ...team, speakingMode: 'assigned' } });
  const state = await invalid.execute();
  assert.equal(state.status, 'failed');
  assert.match(state.error, /成员或任务无效/);
  assert.equal(state.messages.length, 0);
});

test('free speech keeps peer failures visible and cancellation settles all workers without starting summary', { timeout: 10000 }, async t => {
  const { run } = await setup(t, async (_instruction, payload) => {
    if (payload.member.id === 'dev') throw new Error('该专家连接失败');
    if (payload.member.id === 'host') assert.equal(payload.discussion.length, 1);
    return { answer: '可核验的分析' };
  }, { team: { ...team, speakingMode: 'parallel' } });
  assert.equal((await run.execute()).status, 'partial');
  let started;
  const ready = new Promise(resolve => { started = resolve; });
  let count = 0;
  const { run: cancelled } = await setup(t, async (_instruction, payload, signal) => {
    assert.notEqual(payload.member.id, 'host');
    if (++count === 2) started();
    return new Promise((_resolve, reject) => signal.addEventListener('abort', () => reject(new Error('取消')), { once: true }));
  }, { team: { ...team, speakingMode: 'parallel' } });
  const execution = cancelled.execute();
  await ready;
  cancelled.cancel();
  const state = await execution;
  assert.equal(state.status, 'cancelled');
  assert.deepEqual(state.messages.map(message => message.status), ['cancelled', 'cancelled']);
  assert.ok(state.traces.every(trace => trace.status !== 'running'));
});
