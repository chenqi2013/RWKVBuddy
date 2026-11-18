import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, rm, symlink, readFile, realpath } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { indexProject, projectTool, promptWorkspace, resolveProjectPath } from '../src/project-workspace.mjs';
import { AgentRun } from '../src/engine.mjs';

async function fixture(t, trailingSpace = true) {
  const root = await mkdtemp(join(tmpdir(), 'buddy-project-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const project = join(root, trailingSpace ? '工程 ' : '工程');
  await mkdir(join(project, 'src'), { recursive: true });
  await writeFile(join(project, 'README.md'), '# 桌面助手\n支持文件分析\n支持导出\n');
  await writeFile(join(project, 'src/main.dart'), 'void main() {}\n// feature: export');
  return { root, project: await realpath(project) };
}

test('metadata index contains no bodies; tools paginate paths and expose only actual cited lines', async (t) => {
  const { project } = await fixture(t);
  for (let number = 0; number < 260; number++) await writeFile(join(project, 'src', `file-${number}.txt`), `value ${number}`);
  const snapshot = await indexProject(project);
  assert.deepEqual(snapshot.files, {});
  assert.equal(JSON.stringify(snapshot).includes('支持文件分析'), false);
  const evidence = [];
  const list = await projectTool('list_directory', { path: 'src', limit: 2 }, snapshot, evidence);
  assert.equal(list.entries.length, 2);
  assert.equal(list.nextOffset, 2);
  const found = await projectTool('find_files', { pattern: '*file-259.txt' }, snapshot, evidence);
  assert.equal(found.entries[0].path, 'src/file-259.txt');
  const read = await projectTool('read_file', { path: 'README.md', startLine: 2, lineCount: 1 }, snapshot, evidence);
  assert.equal(read.text, '支持文件分析');
  assert.equal(read.nextStartLine, 3);
  assert.deepEqual(evidence[0].ranges, [{ start: 2, end: 2 }]);
  const search = await projectTool('search_text', { path: 'src', query: 'export' }, snapshot, evidence);
  assert.ok(search.scannedFiles <= 80);
  assert.equal(search.hasMore, true);
  let cursor = search.nextOffset;
  let foundMain = false;
  while (cursor != null) {
    const next = await projectTool('search_text', { path: 'src', query: 'export', offset: cursor }, snapshot, evidence);
    foundMain ||= next.matches.some((match) => match.path === 'src/main.dart' && match.line === 2);
    cursor = next.nextOffset;
  }
  assert.equal(foundMain, true);
  await projectTool('read_file', { path: 'src/file-259.txt' }, snapshot, evidence);
  assert.equal(evidence.length, 3);
});

test('project tool rejects traversal, secret/ignored files and paths replaced with symlinks', async (t) => {
  // Git for Windows cannot initialize a directory whose name ends in a space.
  // The other fixtures continue to cover that path-resolution case.
  const { root, project } = await fixture(t, process.platform !== 'win32');
  execFileSync('git', ['init', '--quiet', project]);
  await writeFile(join(project, '.gitignore'), 'private.txt\n');
  await writeFile(join(project, 'private.txt'), 'hidden');
  await writeFile(join(project, 'default-connection.json'), 'hidden');
  const snapshot = await indexProject(project);
  for (const path of ['../outside.txt', '/etc/hosts', 'private.txt', 'default-connection.json']) {
    await assert.rejects(projectTool('read_file', { path }, snapshot, []));
  }
  await writeFile(join(root, 'outside.txt'), 'outside');
  await rm(join(project, 'src/main.dart'));
  await symlink(join(root, 'outside.txt'), join(project, 'src/main.dart'));
  await assert.rejects(projectTool('read_file', { path: 'src/main.dart' }, snapshot, []), /符号链接/);
  const cancelled = new AbortController(); cancelled.abort();
  await assert.rejects(projectTool('list_directory', {}, snapshot, [], cancelled.signal), { name: 'AbortError' });
});

test('leading pasted path resolves a unique trailing-space directory, without interpreting shell text', async (t) => {
  const { project } = await fixture(t);
  const pasted = project.trimEnd() + '\\';
  assert.equal(promptWorkspace(`"${pasted}" 请分析功能`), pasted);
  assert.equal((await resolveProjectPath(pasted)).root, project);
  assert.equal(promptWorkspace('请分析 /tmp/example'), '');
  assert.equal(promptWorkspace('C:\\workspace\\files\\ 请分析工程'), 'C:\\workspace\\files');
  await assert.rejects(resolveProjectPath(project + '-missing'), /不存在/);
});

test('agent explores beyond six calls, recovers errors, saves reads and reuses them after removal', async (t) => {
  const { root, project } = await fixture(t);
  let calls = 0;
  const provider = { generate: async (_instruction, payload) => {
    calls++;
    if (calls === 1) return { progress: '先浏览目录。', tool: 'list_directory', arguments: { path: '.' } };
    if (calls === 2) return { tool: 'read_file', arguments: { path: 'missing.md' } };
    if (calls === 3) {
      assert.match(payload.toolResults.at(-1).result.error, /未索引/);
      return { tool: 'read_file', arguments: { path: 'README.md' } };
    }
    if (calls < 9) return { tool: 'read_file', arguments: { path: 'src/main.dart' } };
    assert.equal(payload.evidence.length, 2);
    return { answer: '桌面文件助手，支持分析和导出。[E1]' };
  } };
  const run = new AgentRun({ question: `"${project.trimEnd()}\\" 请分析项目`, sourceMode: 'text', mode: 'rwkv' }, join(root, 'runs'), () => {}, { provider });
  const state = await run.execute();
  assert.equal(state.status, 'completed', state.error);
  assert.equal(state.workspace, project);
  assert.equal(state.traces.filter((trace) => trace.kind === 'tool').length, 8);
  const snapshotPath = join(run.directory, 'inputs.snapshot.json');
  const saved = JSON.parse(await readFile(snapshotPath, 'utf8'));
  assert.match(saved.files['README.md'].content, /桌面/);
  await rm(project, { recursive: true });
  const followup = { generate: async (_instruction, payload) => payload.toolResults.length
    ? { answer: payload.toolResults[0].result.text }
    : { tool: 'read_file', arguments: { path: 'README.md' } } };
  const next = await new AgentRun({ question: '再看说明', workspace: project, mode: 'rwkv', reuseSnapshot: snapshotPath }, join(root, 'runs'), () => {}, { provider: followup }).execute();
  assert.equal(next.status, 'completed', next.error);
  assert.match(next.answer, /文件分析/);
});
