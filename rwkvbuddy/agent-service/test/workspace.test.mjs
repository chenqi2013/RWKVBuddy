import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { scanWorkspace, financeSnapshot, workspaceFacts } from '../src/workspace.mjs';
import { AgentRun } from '../src/engine.mjs';

async function scratch(t) {
  const root = await mkdtemp(join(tmpdir(), 'rwkvbuddy-workspace-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  return root;
}
async function put(root, path, content) {
  const full = join(root, path);
  await mkdir(join(full, '..'), { recursive: true });
  await writeFile(full, content);
}
const question = '这是一个什么工程，有什么功能，用到了哪些技术栈？';

test('project with nested malformed finance fixtures reaches the model with README, manifests and app entry', async (t) => {
  const root = await scratch(t);
  await put(root, 'README.md', '# 示例工程\nFlutter 桌面文件助手，支持文件分析、工具调用及成果下载。');
  await put(root, 'pubspec.yaml', 'name: example\ndependencies:\n  flutter:\n    sdk: flutter\n');
  await put(root, 'lib/main.dart', 'void main() => runApp(const FileAssistant());');
  await put(root, 'agent-service/package.json', '{"type":"module","dependencies":{"docx":"9.5.1"}}');
  await put(root, 'agent-service/fixtures/shared/tax_rates.tsv', 'not valid tax data');
  await put(root, 'agent-service/fixtures/jobs/group-cash/cash.jsonl', 'not valid JSON');
  const snapshot = await scanWorkspace(root);
  assert.equal(financeSnapshot(snapshot).isFinance, false);
  const facts = workspaceFacts(snapshot);
  assert.equal(facts.files[0].path, 'README.md');
  assert.equal(facts.files[1].path, 'pubspec.yaml');
  assert.ok(facts.evidence.some((source) => source.path === 'lib/main.dart'));
  let called = false;
  const provider = { generate: async (_instruction, payload) => {
    called = true;
    for (const path of ['README.md', 'pubspec.yaml', 'lib/main.dart', 'agent-service/package.json']) {
      assert.ok(payload.sourceTexts.some((source) => source.path === path), path);
    }
    assert.equal(payload.question, question);
    assert.equal(payload.verifiedFacts, undefined);
    return { answer: '这是 Flutter 桌面文件助手，提供分析、工具调用和成果下载，服务使用 Node.js。' };
  } };
  const state = await new AgentRun({ question, sourceMode: 'directory', workspace: root, mode: 'rwkv' }, join(root, 'runs'), () => {}, { provider }).execute();
  assert.equal(state.status, 'completed', state.error);
  assert.ok(called);
  assert.match(state.answer, /Flutter/);
  assert.ok(!state.traces.some((trace) => trace.name.startsWith('lua.')));
  assert.deepEqual(state.warnings, []);
  const local = await new AgentRun({ question, sourceMode: 'directory', workspace: root, mode: 'local' }, join(root, 'runs'), () => {}).execute();
  assert.equal(local.status, 'completed', local.error);
  assert.match(local.answer, /Flutter/);
  assert.ok(!local.traces.some((trace) => trace.name.startsWith('lua.')));
});

test('remote project questions bypass fixed finance parsing even with root-level sample-shaped data', async (t) => {
  const root = await scratch(t);
  await put(root, 'README.md', '# 财务数据导入工具\n使用 Flutter 和 Node.js');
  await put(root, 'jobs/co-x/ledger.csv', 'malformed sample ledger');
  await put(root, 'shared/tax_rates.tsv', 'malformed sample rates');
  const provider = { generate: async (_instruction, payload) => {
    assert.ok(payload.sourceTexts.some((source) => source.path === 'README.md'));
    return { answer: '这是财务数据导入工程，使用 Flutter 和 Node.js。' };
  } };
  const state = await new AgentRun({ question, sourceMode: 'directory', workspace: root, mode: 'rwkv' }, join(root, 'runs'), () => {}, { provider }).execute();
  assert.equal(state.status, 'completed', state.error);
  assert.match(state.answer, /导入工程/);
});

test('large nested fixture sets cannot displace project documentation, manifests or entry points', async (t) => {
  const root = await scratch(t);
  for (let index = 0; index < 260; index++) await put(root, `aaa/fixtures/data-${index}.txt`, 'sample data');
  await put(root, 'README.md', '# Desktop app');
  await put(root, 'pubspec.yaml', 'name: desktop');
  await put(root, 'lib/main.dart', 'void main() {}');
  await put(root, 'agent-service/package.json', '{"type":"module"}');
  await put(root, 'macos/Runner/AppDelegate.swift', 'import Cocoa\nimport FlutterMacOS');
  const snapshot = await scanWorkspace(root);
  assert.equal(Object.keys(snapshot.files).length, 240);
  const initial = workspaceFacts(snapshot).files.slice(0, 45);
  for (const path of ['README.md', 'pubspec.yaml', 'lib/main.dart', 'agent-service/package.json', 'macos/Runner/AppDelegate.swift']) {
    assert.ok(initial.some((file) => file.path === path), path);
  }
  assert.ok(snapshot.warnings.some((warning) => warning.includes('240')));
});

test('directory snapshots exclude ignored private documents and local connection profiles', async (t) => {
  const root = await scratch(t);
  execFileSync('git', ['init', '--quiet', root]);
  await put(root, '.gitignore', '/docs/private.txt\n');
  await put(root, 'README.md', 'safe project description');
  await put(root, 'docs/private.txt', 'sensitive material');
  await put(root, 'agent-service/default-connection.json', '{"apiKey":"do-not-send"}');
  const snapshot = await scanWorkspace(root);
  assert.ok(!snapshot.files['docs/private.txt']);
  assert.ok(!snapshot.files['agent-service/default-connection.json']);
  assert.ok(!JSON.stringify(snapshot).includes('do-not-send'));
  assert.ok(snapshot.files['README.md']);
});


test('explicitly selected directory inside an ignored build tree remains readable', async (t) => {
  const root = await scratch(t);
  execFileSync('git', ['init', '--quiet', root]);
  await put(root, '.gitignore', '/build/\n');
  await put(root, 'build/bundled-demo/README.md', 'bundled sample');
  const snapshot = await scanWorkspace(join(root, 'build/bundled-demo'));
  assert.equal(snapshot.files['README.md'].content, 'bundled sample');
});
