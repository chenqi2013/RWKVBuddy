import readline from 'node:readline';
import { mkdirSync, existsSync, readdirSync, readFileSync, copyFileSync, writeFileSync, renameSync, rmSync, lstatSync } from 'node:fs';
import { join, resolve, dirname, extname, relative, sep, isAbsolute } from 'node:path';
import { homedir } from 'node:os';
import { AgentRun } from './src/engine.mjs';
import { serviceRoot } from './src/runtime.mjs';
import { connection, listModels } from './src/connection.mjs';
import { Provider } from './src/provider.mjs';
import { Pool } from './src/runtime.mjs';
import { defaultConnection } from './src/defaults.mjs';
import { promptWorkspace } from './src/project-workspace.mjs';
import { LocalModels } from './src/local-model.mjs';

const legacyMacRoot = join(homedir(), '.local', 'share', 'RWKVBuddy', 'runs');
const dataRoot = process.env.RWKVBUDDY_DATA_DIR || (process.platform === 'darwin' && existsSync(legacyMacRoot) ? legacyMacRoot :
  join(process.env.APPDATA || join(homedir(), ...(process.platform === 'darwin' ? ['Library', 'Application Support'] : ['.local', 'share'])), 'RWKVBuddy', 'runs'));
mkdirSync(dataRoot, { recursive: true });
const pinsPath = join(dataRoot, 'pinned-runs.json');
let savedPins = [];
try {
  const value = JSON.parse(readFileSync(pinsPath, 'utf8'));
  if (Array.isArray(value)) savedPins = value.filter(id => typeof id === 'string');
} catch {}
const pinnedRuns = new Set(savedPins);
function savePins() {
  writeFileSync(`${pinsPath}.tmp`, JSON.stringify([...pinnedRuns]));
  renameSync(`${pinsPath}.tmp`, pinsPath);
}
let active;
let activePromise;
let shuttingDown = false;
const send = (event) => { if (!process.stdout.destroyed) process.stdout.write(`${JSON.stringify(event)}\n`); };
const localModels = new LocalModels(dataRoot, payload => send({ type: 'local.models', payload }));
const savedRun = (id) => {
  if (typeof id !== 'string' || !/^[a-f0-9-]{36}$/.test(id)) throw new Error('无效任务 ID');
  const state = JSON.parse(readFileSync(join(dataRoot, id, 'run.json'), 'utf8'));
  if (state.status === 'running' && active?.id !== id) {
    state.status = 'interrupted';
    state.error = '上次运行已中断；已保存成果仍可查看，可重新发起任务。';
  }
  return state;
};
function history() {
  return readdirSync(dataRoot, { withFileTypes: true }).filter((e) => e.isDirectory()).flatMap((entry) => {
    try {
      const run = savedRun(entry.name);
      return [{ id: run.id, question: run.question, status: run.status, createdAt: run.createdAt,
        mode: run.mode, workspace: run.workspace, teamName: run.team?.name || '', pinned: pinnedRuns.has(run.id) }];
    } catch { return []; }
  }).sort((a, b) => Number(b.pinned) - Number(a.pinned) || b.createdAt.localeCompare(a.createdAt)).slice(0, 60);
}
function processCommand(command) {
  if (shuttingDown) return;
  try {
    switch (command.type) {
      case 'local.list': localModels.publish(); break;
      case 'local.import':
      case 'local.load':
      case 'local.stop':
      case 'local.remove': {
        void (async () => {
          try {
            if (active && command.type !== 'local.import') throw new Error('请先停止当前任务，再切换或卸载模型');
            let model;
            let profile;
            if (command.type === 'local.import') model = await localModels.import(command.path);
            if (command.type === 'local.load') profile = await localModels.load(command.modelId);
            if (command.type === 'local.stop') await localModels.stop();
            if (command.type === 'local.remove') await localModels.remove(command.modelId);
            send({ type: 'local.result', payload: { requestId: command.requestId, ok: true, model, profile } });
          } catch (error) {
            send({ type: 'local.result', payload: { requestId: command.requestId, ok: false, summary: error.message } });
          }
        })();
        break;
      }
      case 'history': send({ type: 'history', payload: { runs: history() } }); break;
      case 'run.pin': {
        savedRun(command.runId);
        if (typeof command.pinned !== 'boolean') throw new Error('置顶状态无效');
        if (command.pinned) pinnedRuns.add(command.runId); else pinnedRuns.delete(command.runId);
        savePins();
        send({ type: 'history', payload: { runs: history() } });
        break;
      }
      case 'run.delete': {
        savedRun(command.runId);
        if (active?.id === command.runId) throw new Error('请先停止正在运行的任务，再删除');
        const directory = join(dataRoot, command.runId);
        if (lstatSync(directory).isSymbolicLink()) throw new Error('不能删除符号链接任务目录');
        rmSync(directory, { recursive: true });
        pinnedRuns.delete(command.runId);
        savePins();
        send({ type: 'run.deleted', payload: { runId: command.runId } });
        send({ type: 'history', payload: { runs: history() } });
        break;
      }
      case 'load': {
        const run = savedRun(command.runId);
        const turns = [];
        let parent = run.parentRunId;
        while (parent && turns.length < 20) {
          try {
            const previous = savedRun(parent);
            turns.unshift({ id: previous.id, question: previous.question, answer: previous.answer, report: previous.report, status: previous.status, deliverables: previous.deliverables || [], traces: previous.traces || [], events: previous.events || [], team: previous.team || null, messages: previous.messages || [] });
            parent = previous.parentRunId;
          } catch { break; }
        }
        send({ type: 'run.loaded', payload: { run, turns } }); break;
      }
      case 'connection.test': {
        const id = command.requestId;
        void (async () => {
          try {
            const start = Date.now();
            localModels.assertReady(command.config);
            if (command.generate) {
              const provider = new Provider({ ...command.config, maxTokens: 256 }, new Pool(1), localModels);
              const answer = await provider.generate('连接测试。仅返回 {"ok":true}。', {},
                AbortSignal.timeout(command.config?.inferenceMode === 'local' ? 120000 : 20000));
              if (answer.ok !== true) throw new Error('服务已响应，但生成测试未返回预期的 JSON');
              send({ type: 'connection.result', payload: { requestId: id, ok: true, generation: true,
                latencyMs: Date.now() - start, summary: '生成测试通过，服务已返回有效回答' } });
            } else {
              const result = command.config?.localModelId
                ? { models: [command.config.model], summary: '本地原生模型已就绪' }
                : await listModels(command.config);
              send({ type: 'connection.result', payload: { requestId: id, ok: true, ...result } });
            }
          } catch (error) { send({ type: 'connection.result', payload: { requestId: id, ok: false, summary: error.message } }); }
        })();
        break;
      }
      case 'run': {
        if (active) throw new Error('已有任务运行中，请先取消或等待完成');
        if (typeof command.question !== 'string' || !command.question.trim() || command.question.length > 8000) throw new Error('请输入 1–8000 字的任务指令');
        if (command.parentRunId) {
          const parent = savedRun(command.parentRunId);
          command.context = { question: parent.question, report: (parent.answer || parent.report || '').slice(0, 16000) };
          if (parent.team) command.context.discussion = (parent.messages || []).filter(message => message.status === 'completed')
            .map(({ roleId, name, content }) => ({ roleId, name, content: content.slice(0, 2000) }));
          const turns = [];
          let previous = parent;
          let remaining = 16000;
          while (previous && turns.length < 12 && remaining > 0) {
            const answer = (previous.answer || previous.report || '').slice(0, Math.min(5000, remaining));
            const question = previous.question.slice(0, 2000);
            turns.unshift({ question, answer });
            remaining -= question.length + answer.length;
            try { previous = previous.parentRunId ? savedRun(previous.parentRunId) : null; } catch { break; }
          }
          command.context.turns = turns;
          command.conversationId = parent.conversationId || parent.id;
          if (command.reuseInputs) {
            const outputSnapshot = join(dataRoot, parent.id, 'outputs.snapshot.json');
            const previousSnapshot = existsSync(outputSnapshot) ? outputSnapshot : join(dataRoot, parent.id, 'inputs.snapshot.json');
            if (!existsSync(previousSnapshot)) throw new Error('该历史任务缺少可复用资料，请重新添加文件');
            command.reuseSnapshot = previousSnapshot;
            command.sourceMode = parent.sourceMode || 'directory';
            command.selectedFiles = parent.selectedFiles || [];
            command.workspace = parent.workspace || '';
          }
        }
        if (promptWorkspace(command.question)) {
          command.sourceMode = 'text';
        }
        if (command.sourceMode === 'files') {
          if (!Array.isArray(command.selectedFiles) || !command.selectedFiles.length || command.selectedFiles.length > 20 ||
              command.selectedFiles.some((path) => typeof path !== 'string' || !path.trim() || path.length > 32767)) throw new Error('请选择 1–20 个有效文件');
        } else if (command.sourceMode !== 'text' && (typeof command.workspace !== 'string' || !command.workspace.trim())) throw new Error('请选择工作目录');
        if (!['local', 'rwkv'].includes(command.mode)) throw new Error('请选择有效执行模式');
        if (command.mode === 'rwkv') {
          if (!command.config?.localModelId) connection(command.config);
          localModels.assertReady(command.config);
        }
        active = new AgentRun({ ...command, workspace: ['files', 'text'].includes(command.sourceMode) ? '' : resolve(command.workspace) }, dataRoot, send, { nativeModels: localModels });
        activePromise = active.execute().catch(() => send({ type: 'service.error', payload: { message: '运行记录写入失败，请检查用户数据目录权限' } })).finally(() => {
          active = null; activePromise = null;
          send({ type: 'history', payload: { runs: history() } });
        });
        break;
      }
      case 'cancel': if (active && (!command.runId || command.runId === active.id)) active.cancel(); break;
      case 'export.file': {
        const run = savedRun(command.runId);
        const file = run.deliverables?.find((item) => item.id === command.fileId);
        if (!file) throw new Error('找不到该成果文件');
        const source = join(dataRoot, run.id, 'outputs', file.name);
        const target = resolve(command.path || '');
        if (extname(target).toLowerCase() !== extname(file.name).toLowerCase()) throw new Error('保存格式必须与成果文件一致');
        const inside = relative(resolve(dataRoot), target);
        if (inside === '' || (!isAbsolute(inside) && inside !== '..' && !inside.startsWith(`..${sep}`))) {
          throw new Error('请将文件保存到任务数据目录之外');
        }
        mkdirSync(dirname(target), { recursive: true });
        copyFileSync(source, target);
        send({ type: 'file.exported', payload: { path: target } });
        break;
      }
      case 'export.trace': {
        const run = savedRun(command.runId);
        const target = resolve(command.path || '');
        if (!target.toLowerCase().endsWith('.json')) throw new Error('请选择 .json 轨迹路径');
        if (target.startsWith(resolve(dataRoot) + '\\') || target.startsWith(resolve(dataRoot) + '/')) throw new Error('请将轨迹导出到任务数据目录之外');
        mkdirSync(dirname(target), { recursive: true });
        writeFileSync(target, JSON.stringify({ version: 1, runId: run.id, question: run.question,
          status: run.status, traces: run.traces, events: run.events }, null, 2));
        send({ type: 'trace.exported', payload: { path: target } });
        break;
      }
      case 'export': {
        const run = savedRun(command.runId);
        if (!run.reportPath || !existsSync(run.reportPath)) throw new Error('此任务还没有报告');
        const target = resolve(command.path || '');
        if (!target.toLowerCase().endsWith('.md')) throw new Error('请选择 .md 报告路径');
        if (target !== run.reportPath) { mkdirSync(dirname(target), { recursive: true }); copyFileSync(run.reportPath, target); }
        send({ type: 'report.exported', payload: { path: target } });
        break;
      }
      case 'shutdown': void shutdown(); break;
      default: throw new Error('未知本地服务命令');
    }
  } catch (error) { send({ type: 'service.error', payload: { message: error.message } }); }
}
async function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  active?.cancel();
  if (activePromise) await activePromise;
  await localModels.close();
  process.exitCode = 0;
  input.close();
  process.stdin.destroy();
}
const input = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
input.on('line', (line) => {
  if (line.length > 1024 * 1024) { send({ type: 'service.error', payload: { message: '命令超过大小限制' } }); return; }
  try { processCommand(JSON.parse(line)); }
  catch { send({ type: 'service.error', payload: { message: '无效 JSON 命令' } }); }
});
input.on('close', () => { if (!shuttingDown) void shutdown(); });
process.on('SIGTERM', () => { void shutdown(); });
process.on('SIGINT', () => { void shutdown(); });
process.stdout.on('error', () => { void shutdown(); });
send({ type: 'service.ready', payload: {
  protocolVersion: 1, sampleWorkspace: join(serviceRoot, 'fixtures'), dataRoot,
  baseUrl: process.env.FOREMAN_BASE_URL || defaultConnection.baseUrl,
  model: process.env.FOREMAN_MODEL || defaultConnection.model,
  defaultConnection, hasEnvironmentCredentials: Boolean(process.env.FOREMAN_PASSWORD),
  runs: history(),
  localModels: localModels.snapshot(),
} });
