// Read-only probes of a foreman-cli working copy. Model/network responses are mocked.
// Run from foreman-cli: node --import tsx <this-file> <foreman-root> <output-json>
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawn } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const root = resolve(process.argv[2]);
const outputPath = process.argv[3];
const load = (file) => import(pathToFileURL(join(root, 'src', file)).href);
const { RwkvBatchClient } = await load('rwkv-batch.ts');
const { runSessionsInWaves } = await load('session.ts');
const { filesForJob } = await load('jobs.ts');
const { groundAnswers, localLuaAnswer } = await load('finance.ts');
const results = [];
const delay = (ms) => new Promise((done) => setTimeout(done, ms));
const tool = (name, args = {}) => JSON.stringify({ name, arguments: args });
const settings = {
  maxTokens: 100, temperature: 0.1, topK: 50, topP: 0.3,
  alphaPresence: 0, alphaFrequency: 0, alphaDecay: 0.99, chunkSize: 1, stop: [],
};
const newClient = (wave = 2) => new RwkvBatchClient(
  'http://mock.invalid/v1', 'mock', '', 0, settings, 'rwkv_lightning_cuda', wave,
);
const spec = (client, label, handle) => ({
  client, label, handle, user: label, files: { [`${label}.txt`]: label },
  maxTurns: 3, maxTokens: 100, temperature: 0.1, topP: 0.3,
});
async function probe(id, fn) {
  try {
    results.push({ id, status: 'confirmed', evidence: await fn() });
  } catch (error) {
    results.push({ id, status: 'probe_failed', error: String(error) });
    process.exitCode = 1;
  }
}

await probe('P01_windows_async_lua', async () => {
  let live = 0;
  let peak = 0;
  let heartbeat = 0;
  const ticker = setInterval(() => { heartbeat++; }, 10);
  const bundledLua = join(root, 'runtime', process.platform === 'win32' ? 'lua.exe' : 'lua');
  const lua = process.env.FOREMAN_LUA_PATH || (existsSync(bundledLua) ? bundledLua : 'lua');
  const run = () => new Promise((done, fail) => {
    const child = spawn(lua, ['-'], { windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (data) => { stdout += data; });
    child.stderr.on('data', (data) => { stderr += data; });
    child.on('spawn', () => { live++; peak = Math.max(peak, live); });
    child.once('error', fail);
    child.once('close', (code) => {
      live--;
      code === 0 ? done(stdout.trim()) : fail(new Error(stderr || `exit=${code}`));
    });
    child.stdin.end('local t=os.clock(); while os.clock()-t<0.20 do end; print("ok")');
  });
  try {
    const outputs = await Promise.all([run(), run()]);
    assert.equal(peak, 2);
    assert.deepEqual(outputs, ['ok', 'ok']);
    assert.ok(heartbeat > 0);
    return { platform: process.platform, peakLiveChildProcesses: peak, eventLoopHeartbeat: heartbeat, outputs,
      scope: 'OS child-process overlap; not a model-throughput benchmark' };
  } finally { clearInterval(ticker); }
});

await probe('P02_batch_waves_are_sequential', async () => {
  const original = globalThis.fetch;
  let live = 0;
  let peak = 0;
  const sizes = [];
  globalThis.fetch = async (_url, options) => {
    const body = JSON.parse(options.body);
    sizes.push(body.contents.length);
    live++; peak = Math.max(peak, live);
    await delay(20);
    live--;
    return new Response(body.contents.map((prompt, index) =>
      `data: ${JSON.stringify({ choices: [{ index, text: prompt }] })}\n\n`).join(''));
  };
  try {
    const outputs = await newClient(2).completeMany(['a', 'b', 'c', 'd', 'e'].map((prompt) => ({ prompt })));
    assert.deepEqual(sizes, [2, 2, 1]);
    assert.equal(peak, 1);
    assert.deepEqual(outputs, ['a', 'b', 'c', 'd', 'e']);
    return { mocked: true, prompts: 5, waveSize: 2, requestBatchSizes: sizes, peakConcurrentRequests: peak };
  } finally { globalThis.fetch = original; }
});

await probe('P03_worker_tools_are_sequential', async () => {
  let generation = 0;
  let live = 0;
  let peak = 0;
  const client = { completeMany: async (items) => {
    generation++;
    return items.map(() => generation === 1
      ? tool('read_file', { path: 'a.txt' }) : tool('submit', { answer: 'ok' }));
  } };
  const handle = async (name, args, env) => {
    if (name === 'submit') return env.call(name, args);
    live++; peak = Math.max(peak, live);
    await delay(20);
    live--;
    return 'ok';
  };
  const answers = await runSessionsInWaves([spec(client, 'a', handle), spec(client, 'b', handle)]);
  assert.equal(peak, 1);
  assert.deepEqual(answers.map((answer) => answer.submitted), ['ok', 'ok']);
  return { mocked: true, independentWorkers: 2, peakConcurrentAsyncToolHandlers: peak };
});

await probe('P04_tool_failure_aborts_siblings', async () => {
  let siblingHandled = false;
  const client = { completeMany: async () => [tool('read_file'), tool('read_file')] };
  await assert.rejects(runSessionsInWaves([
    spec(client, 'a', async () => { throw new Error('injected-tool-failure'); }),
    spec(client, 'b', async () => { siblingHandled = true; return 'ok'; }),
  ]), /injected-tool-failure/);
  assert.equal(siblingHandled, false);
  return { mocked: true, wholeRunRejected: true, siblingToolExecuted: siblingHandled };
});

await probe('P05_file_views_are_separate', async () => {
  const seen = {};
  const client = { completeMany: async () => [tool('submit', { answer: 'ok' }), tool('submit', { answer: 'ok' })] };
  const capture = (label) => (name, args, env) => { seen[label] = Object.keys(env.files); return env.call(name, args); };
  await runSessionsInWaves([spec(client, 'a', capture('a')), spec(client, 'b', capture('b'))]);
  assert.deepEqual(seen, { a: ['a.txt'], b: ['b.txt'] });
  return { mocked: true, sessionFiles: seen, scope: 'logical VirtualFs isolation; not OS process isolation' };
});

await probe('P06_grounding_checks_only_profit_or_net', async () => {
  const all = Object.fromEntries(['jobs/co-north/ledger.csv', 'shared/tax_rates.tsv'].map((file) =>
    [file, readFileSync(join(root, 'fixtures', file), 'utf8')]));
  const job = { id: 'co-north', files: Object.keys(all), prompt: 'entity=north' };
  const filesFor = (id, hinted) => filesForJob(id, all, hinted);
  const local = localLuaAnswer(job, filesFor(job.id, job.files));
  assert.ok(local?.includes('profit=450500.00'));
  const incorrect = local.replace('rev=1280000.00', 'rev=1.00');
  const grounded = groundAnswers([job], [{ id: job.id, submitted: incorrect, turns: 1, toolCalls: 1 }], all, filesFor);
  assert.equal(grounded[0].submitted, incorrect);
  const fallback = groundAnswers([job], [{ id: job.id, submitted: null, turns: 0, toolCalls: 0 }], all, filesFor);
  assert.equal(fallback[0].submitted, local);
  return { local, submittedWithIncorrectRevenue: incorrect, incorrectRevenuePreserved: true,
    nullSubmissionFilledLocally: true, hasExplicitFallbackProvenance: 'source' in fallback[0] };
});

await probe('P07_sse_unterminated_last_line', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async () => new Response('data: {"choices":[{"index":0,"text":"tail"}]}');
  try {
    const outputs = await newClient().completeMany([{ prompt: 'a' }]);
    assert.deepEqual(outputs, ['']);
    return { mocked: true, unterminatedFinalSseLineDiscarded: true, outputs,
      scope: 'truncated/unterminated stream edge case' };
  } finally { globalThis.fetch = original; }
});

await probe('P08_batch_uses_first_item_settings', async () => {
  const original = globalThis.fetch;
  let transmittedMaxTokens;
  globalThis.fetch = async (_url, options) => {
    transmittedMaxTokens = JSON.parse(options.body).max_tokens;
    return new Response('data: {"choices":[{"index":0,"text":"a"},{"index":1,"text":"b"}]}\n\n');
  };
  try {
    await newClient().completeMany([{ prompt: 'a', maxTokens: 11 }, { prompt: 'b', maxTokens: 99 }]);
    assert.equal(transmittedMaxTokens, 11);
    return { mocked: true, requestedMaxTokens: [11, 99], transmittedSharedMaxTokens: transmittedMaxTokens };
  } finally { globalThis.fetch = original; }
});

const report = {
  observedAtUtc: new Date().toISOString(), referenceRoot: root, node: process.version,
  platform: process.platform, liveInferenceTested: false, results,
  sourceSha256: Object.fromEntries([
    'src/session.ts', 'src/jobs.ts', 'src/rwkv-batch.ts', 'src/tools.ts',
    'src/finance.ts', 'src/repl.ts', 'src/view.ts', 'src/sketches.ts',
    'src/workspace.ts', 'scripts/package-windows.ps1',
  ].filter((file) => existsSync(join(root, file))).map((file) => [
    file, createHash('sha256').update(readFileSync(join(root, file))).digest('hex'),
  ])),
};
if (outputPath) writeFileSync(resolve(outputPath), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify(report, null, 2));
