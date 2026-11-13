import readline from 'node:readline';
import { mkdirSync, existsSync, readdirSync, readFileSync, copyFileSync, writeFileSync } from 'node:fs';
import { join, resolve, dirname, extname, relative, sep, isAbsolute } from 'node:path';
import { homedir } from 'node:os';
import { AgentRun } from './src/engine.mjs';
import { serviceRoot } from './src/runtime.mjs';
import { connection, listModels } from './src/connection.mjs';
import { Provider } from './src/provider.mjs';
import { Pool } from './src/runtime.mjs';
import { defaultConnection } from './src/defaults.mjs';

const legacyMacRoot = join(homedir(), '.local', 'share', 'RWKVBuddy', 'runs');
const dataRoot = process.env.RWKVBUDDY_DATA_DIR || (process.platform === 'darwin' && existsSync(legacyMacRoot) ? legacyMacRoot :
  join(process.env.APPDATA || join(homedir(), ...(process.platform === 'darwin' ? ['Library', 'Application Support'] : ['.local', 'share'])), 'RWKVBuddy', 'runs'));
mkdirSync(dataRoot, { recursive: true });
let active;
let activePromise;
let shuttingDown = false;
const send = (event) => { if (!process.stdout.destroyed) process.stdout.write(`${JSON.stringify(event)}\n`); };
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
        mode: run.mode, workspace: run.workspace }];
    } catch { return []; }
  }).sort((a, b) => b.createdAt.localeCompare(a.createdAt)).slice(0, 60);
}
function processCommand(command) {
  if (shuttingDown) return;
  try {
    switch (command.type) {
      case 'history': send({ type: 'history', payload: { runs: history() } }); break;
      case 'load': {
        const run = savedRun(command.runId);
        const turns = [];
        let parent = run.parentRunId;
        while (parent && turns.length < 20) {
          try {
            const previous = savedRun(parent);
            turns.unshift({ id: previous.id, question: previous.question, answer: previous.answer, report: previous.report, status: previous.status, deliverables: previous.deliverables || [], traces: previous.traces || [], events: previous.events || [] });
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
            if (command.generate) {
              const provider = new Provider({ ...command.config, maxTokens: 256 }, new Pool(1));
              const answer = await provider.generate('连接测试。仅返回 {"ok":true}。', {}, AbortSignal.timeout(20000));
              if (answer.ok !== true) throw new Error('服务已响应，但生成测试未返回预期的 JSON');
              send({ type: 'connection.result', payload: { requestId: id, ok: true, generation: true,
                latencyMs: Date.now() - start, summary: '生成测试通过，服务已返回有效回答' } });
            } else {
              send({ type: 'connection.result', payload: { requestId: id, ok: true, ...await listModels(command.config) } });
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
        if (command.sourceMode === 'files') {
          if (!Array.isArray(command.selectedFiles) || !command.selectedFiles.length || command.selectedFiles.length > 20 ||
              command.selectedFiles.some((path) => typeof path !== 'string' || !path.trim() || path.length > 32767)) throw new Error('请选择 1–20 个有效文件');
        } else if (command.sourceMode !== 'text' && (typeof command.workspace !== 'string' || !command.workspace.trim())) throw new Error('请选择工作目录');
        if (!['local', 'rwkv'].includes(command.mode)) throw new Error('请选择有效执行模式');
        if (command.mode === 'rwkv') connection(command.config);
        active = new AgentRun({ ...command, workspace: ['files', 'text'].includes(command.sourceMode) ? '' : resolve(command.workspace) }, dataRoot, send);
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
} });
