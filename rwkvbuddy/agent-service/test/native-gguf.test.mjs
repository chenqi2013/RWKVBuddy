import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { LocalModels } from '../src/local-model.mjs';
import { Provider } from '../src/provider.mjs';
import { Pool } from '../src/runtime.mjs';

test('real GGUF loads, streams Chinese JSON, cancels and reuses memory without HTTP', { skip: !process.env.GGUF_TEST_PATH, timeout: 180000 }, async t => {
  const root = await mkdtemp(join(tmpdir(), 'buddy-native-real-'));
  const states = [];
  const manager = new LocalModels(root, value => states.push(value.state));
  t.after(async () => { await manager.close(); await rm(root, { recursive: true, force: true }); });
  t.mock.method(globalThis, 'fetch', () => { throw new Error('HTTP must not be used'); });
  const record = await manager.import(process.env.GGUF_TEST_PATH);
  const profile = await manager.load(record.id);
  assert.equal(profile.baseUrl, '');
  assert.equal(profile.protocol, 'native');
  assert.ok(states.some(state => state.progress > 0));
  const child = manager.session.child;
  console.log(`Native worker PID: ${child.pid}, transport: ${manager.state.transport}`);
  if (process.platform === 'win32') {
    const { stdout } = await promisify(execFile)('powershell.exe', ['-NoProfile', '-Command',
      `$ErrorActionPreference='Stop'; @(Get-NetTCPConnection | Where-Object OwningProcess -eq ${child.pid}).Count`], { windowsHide: true });
    assert.equal(stdout.trim(), '0', 'Native worker must not open TCP connections or listen on ports');
  }
  const updates = [];
  const provider = new Provider({ ...profile, temperature: 0 }, new Pool(1), manager);
  const answer = await provider.generate('计算用户提出的乘法，将计算结果以数字字符串放入 JSON 的 answer 字段。', { question: '36乘以12等于多少？' }, new AbortController().signal,
    (_length, text) => updates.push(text));
  assert.equal(String(answer.answer), '432');
  assert.ok(updates.length > 4);
  assert.ok(updates.every(text => !text.includes('�')));
  const chinese = await provider.generate('仅返回 {"answer":"你好，世界"}。', {}, new AbortController().signal);
  assert.equal(chinese.answer, '你好，世界');
  const controller = new AbortController();
  await assert.rejects(provider.generate('生成一个含一百个城市说明的 JSON。', {}, controller.signal, (length) => { if (length > 5) controller.abort(); }), { name: 'AbortError' });
  const repeated = await provider.generate('仅返回 {"ok":true}。', {}, new AbortController().signal);
  assert.equal(repeated.ok, true);
  assert.equal(globalThis.fetch.mock.callCount(), 0);
  assert.equal(manager.state.status, 'ready');
  await manager.stop();
  assert.ok(child.exitCode !== null || child.signalCode !== null);
});
