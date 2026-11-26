import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile, access } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { LocalModels, inspectGGUF, runtimePath } from '../src/local-model.mjs';
import { Provider } from '../src/provider.mjs';
import { Pool } from '../src/runtime.mjs';

async function fixture(t, options = {}) {
  const { mode = 'normal', ...managerOptions } = options;
  const root = await mkdtemp(join(tmpdir(), 'buddy-gguf-'));
  const path = join(root, '中文 模型.gguf');
  const header = Buffer.alloc(64);
  header.write('GGUF'); header.writeUInt32LE(3, 4); header.writeBigUInt64LE(1n, 8);
  await writeFile(path, header);
  const fake = join(root, 'fake-native.mjs');
  await writeFile(fake, `
import readline from 'node:readline';
const mode=${JSON.stringify(mode)};
const timers=new Map();
const send=(value)=>console.log(JSON.stringify(value));
const input=readline.createInterface({input:process.stdin});
input.on('line',line=>{
 const c=JSON.parse(line);
 if(c.type==='shutdown'){process.exit(0);}
 if(c.type==='cancel'){
   if(mode==='ignore-cancel')return;
   clearTimeout(timers.get(c.id));
   setTimeout(()=>send({type:'error',id:c.id,message:'cancelled'}),25); return;
 }
 if(c.type==='load'){
   console.error('native loading '+c.path);
   if(mode==='crash'){process.exit(3);return;}
   if(mode==='hang')return;
   send({type:'progress',percent:50});
   timers.set(c.id,setTimeout(()=>send({type:'ready',id:c.id,context:8192}),100));
 }
 if(c.type==='generate'){
   send({type:'delta',id:c.id,text:'{"answer":"中文',completion_tokens:3});
   timers.set(c.id,setTimeout(()=>{
     send({type:'delta',id:c.id,text:'"}',completion_tokens:4});
     send({type:'done',id:c.id,finish_reason:'stop',completion_tokens:4,prompt_tokens:10});
   },100));
 }
});
`);
  let child;
  let args;
  const states = [];
  const manager = new LocalModels(root, payload => states.push(payload.state), { executable: process.execPath,
    launch: (a, opts) => { args = a; child = spawn(process.execPath, [fake, ...a], opts); return child; }, ...managerOptions });
  t.after(async () => { await manager.close(); await rm(root, { recursive: true, force: true }); });
  return { manager, root, path, states, get child() { return child; }, get args() { return args; } };
}

test('GGUF import preserves originals, deduplicates paths and restores records without inference', async t => {
  const { manager, path, root } = await fixture(t);
  const model = await manager.import(path);
  assert.equal((await manager.import(path)).id, model.id);
  const restored = new LocalModels(root, () => {});
  assert.equal(restored.models[0].path, model.path);
  assert.equal(restored.state.status, 'idle');
  assert.throws(() => restored.assertReady({ localModelId: model.id }), /加载/);
  await manager.remove(model.id);
  await access(path);
  assert.deepEqual(JSON.parse(await readFile(join(root, 'local-models.json'), 'utf8')), []);
});

test('GGUF rejects invalid headers and maps native runtimes for Windows and macOS', async t => {
  const { path, root } = await fixture(t);
  await assert.rejects(inspectGGUF(join(root, 'old.pth')), /gguf/);
  await writeFile(path, Buffer.alloc(24));
  await assert.rejects(inspectGGUF(path), /有效/);
  await writeFile(path, 'GGUF');
  await assert.rejects(inspectGGUF(path), /完整/);
  assert.match(runtimePath('root', 'win32', 'arm64'), /windows-arm64.*rwkvbuddy-inference.exe/);
  assert.match(runtimePath('root', 'darwin', 'x64'), /macos-x64.*rwkvbuddy-inference/);
});

test('native handshake and streaming use pipes without addresses, ports or fetch', async t => {
  const f = await fixture(t);
  t.mock.method(globalThis, 'fetch', () => { throw new Error('HTTP forbidden'); });
  const model = await f.manager.import(f.path);
  const profile = await f.manager.load(model.id);
  assert.equal(f.manager.state.transport, 'stdio');
  assert.equal(profile.protocol, 'native');
  assert.equal(profile.baseUrl, '');
  assert.deepEqual(f.args, []);
  assert.ok(f.states.some(state => state.progress === 50));
  f.manager.assertReady(profile);
  assert.throws(() => f.manager.assertReady({ ...profile, localModelId: 'other' }), /加载/);
  const updates = [];
  const answer = await new Provider(profile, new Pool(1), f.manager).generate('分析', {}, new AbortController().signal,
    (_length, text, info) => updates.push({ text, info }));
  assert.deepEqual(answer, { answer: '中文' });
  assert.equal(updates.at(-1).info.generation.completionTokens, 4);
  assert.equal(globalThis.fetch.mock.callCount(), 0);
  await f.manager.stop();
  assert.equal(f.manager.state.status, 'idle');
  assert.ok(f.child.exitCode !== null || f.child.signalCode !== null);
});

test('load cancellation rejects overlaps and releases its process and slot', async t => {
  const { manager, path } = await fixture(t);
  const model = await manager.import(path);
  const loading = manager.load(model.id);
  const rejection = assert.rejects(loading);
  while (manager.state.status !== 'loading') await new Promise(resolve => setTimeout(resolve, 5));
  await assert.rejects(manager.load(model.id), /正在加载/);
  await manager.stop();
  await rejection;
  assert.equal(manager.state.status, 'idle');
  await manager.load(model.id);
  assert.equal(manager.state.status, 'ready');
});

test('generation cancellation waits for native acknowledgement before reusing memory', async t => {
  const { manager, path } = await fixture(t);
  const model = await manager.import(path);
  const profile = await manager.load(model.id);
  const provider = new Provider(profile, new Pool(2), manager);
  const controller = new AbortController();
  const cancelled = provider.generate('分析', {}, controller.signal, length => { if (length) controller.abort(); });
  const rejection = assert.rejects(cancelled, { name: 'AbortError' });
  const next = provider.generate('下一次', {}, new AbortController().signal);
  await rejection;
  assert.deepEqual(await next, { answer: '中文' });
  assert.equal(manager.pool.active, 0);
});

test('missing native runtime keeps model records and reports a useful error', async t => {
  const { manager, path } = await fixture(t, { executable: join(tmpdir(), 'missing-buddy-runtime.exe') });
  const model = await manager.import(path);
  await assert.rejects(manager.load(model.id), /推理运行时/);
  assert.equal(manager.models.length, 1);
  assert.equal(manager.snapshot().runtimeAvailable, false);
});

for (const mode of ['crash', 'hang']) {
  test(`native ${mode} failure preserves diagnostics and releases the process`, async t => {
    const { manager, path } = await fixture(t, { mode, timeout: 250, cancelTimeout: 100 });
    const model = await manager.import(path);
    await assert.rejects(manager.load(model.id));
    assert.equal(manager.state.status, 'failed');
    assert.match(manager.state.detail, /native loading/);
    assert.equal(manager.session, null);
    assert.equal(manager.loading, false);
  });
}

test('unresponsive cancellation stops the worker instead of reusing active inference', async t => {
  const { manager, path } = await fixture(t, { mode: 'ignore-cancel', cancelTimeout: 20 });
  const model = await manager.import(path);
  const profile = await manager.load(model.id);
  const controller = new AbortController();
  await assert.rejects(new Provider(profile, new Pool(1), manager).generate('分析', {}, controller.signal, length => { if (length) controller.abort(); }));
  assert.equal(manager.state.status, 'failed');
  assert.throws(() => manager.assertReady(profile), /加载/);
});
