// Real-model contract probes. Requires a running local server; no mocked output.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { Provider } from '../agent-service/src/provider.mjs';
import { listModels } from '../agent-service/src/connection.mjs';
import { Pool } from '../agent-service/src/runtime.mjs';
import { AgentRun } from '../agent-service/src/engine.mjs';

const args = process.argv.slice(2);
if (args.includes('--help')) {
  console.log('Usage: node scripts/evaluate-local-rwkv.mjs [http://127.0.0.1:8099/v1] [--workflow]');
  process.exit(0);
}
if (args.some((arg) => arg.startsWith('--') && arg !== '--workflow')) throw new Error('Unknown option');
const evaluationRoot = resolve('build/model-evaluation', `rwkv-${Date.now()}`);

const config = {
  baseUrl: args.find((arg) => !arg.startsWith('--')) || 'http://127.0.0.1:8099/v1',
  inferenceMode: 'local', protocol: 'python', model: '', concurrency: 1,
  maxTokens: 512, temperature: 0,
};
const models = await listModels(config);
if (!models.models.length) throw new Error('No loaded local model');
config.model = models.models[0];
const provider = new Provider(config, new Pool(1));
const cases = [
  { id: 'json', instruction: '仅提交 {"ok":true}。', data: {}, verify: (r) => r.ok === true },
  { id: 'facts', instruction: '提取资料中的合同号和金额，返回 {"contractId":string,"amount":number}，不增加事实。',
    data: { text: '合同 HT-003，含税总额 860 元；尚未付款。' }, verify: (r) => r.contractId === 'HT-003' && r.amount === 860 },
  { id: 'tool-request', instruction: '计算 36*12。现在必须先调用 calculator 工具，尚未获得工具结果。提交 {"tool":"calculator","arguments":{"expression":"36*12"}}。',
    data: {}, verify: (r) => r.tool === 'calculator' && r.arguments?.expression?.replace(/\s/g, '') === '36*12' },
  { id: 'tool-result', instruction: '工具已经执行，不要再次调用。根据结果提交 {"answer":"计算结果"}。',
    data: { toolResults: [{ tool: 'calculator', arguments: { expression: '36*12' }, result: 432 }] },
    verify: (r) => !r.tool && typeof r.answer === 'string' && /432/.test(r.answer) },
  { id: 'missing-fact', instruction: '资料没有给出付款日期，请不要猜测；提交 {"paymentDate":null}。',
    data: { text: '合同 HT-003，含税总额 860 元；尚未付款。' }, verify: (r) => r.paymentDate === null },
];
const results = [];
for (const item of cases) {
  const started = performance.now();
  let firstTextMs;
  try {
    const response = await provider.generate(item.instruction, item.data, AbortSignal.timeout(600000), (length) => {
      if (length && firstTextMs === undefined) firstTextMs = Math.round(performance.now() - started);
    });
    results.push({ id: item.id, passed: item.verify(response), response, firstTextMs, durationMs: Math.round(performance.now() - started) });
  } catch (error) {
    results.push({ id: item.id, passed: false, error: error.message, firstTextMs, durationMs: Math.round(performance.now() - started) });
  }
  console.log(JSON.stringify(results.at(-1)));
}
mkdirSync(evaluationRoot, { recursive: true });
if (args.includes('--workflow')) {
  const attachment = join(evaluationRoot, '合同.txt');
  writeFileSync(attachment, '合同号：HT-003\n单价：36 元\n数量：12 件\n付款日期：未提供\n');
  const run = new AgentRun({
    mode: 'rwkv', sourceMode: 'files', selectedFiles: [attachment], outputMode: 'files', config,
    question: '读取附件，先调用 calculator 计算合同总额，再生成结果.json，字段为 contractId（合同号）、amount（数字金额）、paymentDate（原文未给出时 null）。简短回答并引用资料。不要猜测缺失事实。',
  }, join(evaluationRoot, 'runs'), () => {});
  const timer = setTimeout(() => run.cancel(), 600000);
  const started = performance.now();
  try {
    const state = await run.execute();
    const file = state.deliverables.find((item) => item.name === '结果.json');
    const actual = file ? JSON.parse(readFileSync(file.path, 'utf8')) : null;
    const calculation = state.traces.some((trace) => trace.name === 'calculator'
      && trace.status === 'completed' && JSON.parse(trace.output).result === 432);
    const passed = state.status === 'completed' && calculation && actual?.contractId === 'HT-003'
      && actual.amount === 432 && actual.paymentDate === null && /\[E\d+\]/.test(state.answer);
    results.push({ id: 'attachment-tool-delivery', passed, status: state.status, actual, calculation,
      answer: state.answer, error: state.error, runDirectory: run.directory, durationMs: Math.round(performance.now() - started) });
  } catch (error) {
    results.push({ id: 'attachment-tool-delivery', passed: false, error: error.message, durationMs: Math.round(performance.now() - started) });
  } finally { clearTimeout(timer); }
  console.log(JSON.stringify(results.at(-1)));
}
const file = join(evaluationRoot, 'results.json');
writeFileSync(file, JSON.stringify({ model: config.model, timestamp: new Date().toISOString(),
  scope: 'Contract probes only; not proof of document analysis quality or long-context recall', results }, null, 2));
console.log(`Passed ${results.filter((r) => r.passed).length}/${results.length}; evidence: ${file}`);
if (results.some((r) => !r.passed)) process.exitCode = 1;
