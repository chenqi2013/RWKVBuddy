import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { connection, listModels } from '../src/connection.mjs';
import { Provider } from '../src/provider.mjs';
import { Pool } from '../src/runtime.mjs';
import { analysisTool, calculate } from '../src/analysis-tools.mjs';

test('connection accepts base, model and completion URLs for each transport', () => {
  for (const suffix of ['', '/', '/v1', '/v1/', '/v1/models', '/v1/chat/completions', '/v1/batch/completions']) {
    for (const protocol of ['rwkv', 'python', 'chat']) {
      const target = connection({ baseUrl: `https://example.test${suffix}`, protocol });
      assert.equal(target.baseUrl, 'https://example.test/v1');
      assert.equal(target.endpoint, `https://example.test/v1/${protocol === 'rwkv' ? 'batch' : 'chat'}/completions`);
    }
  }
  assert.equal(connection({ baseUrl: 'https://example.test/proxy/v1/models' }).baseUrl, 'https://example.test/proxy/v1');
  for (const baseUrl of ['file:///test', 'https://secret:password@example.test', 'https://example.test?secret=x']) assert.throws(() => connection({ baseUrl }));
  for (const headers of [{ Host: 'other' }, { 'X-Key': 'value\nInjected: true' }]) assert.throws(() => connection({ headers }));
});

test('Python raw transport and model discovery use different routes and preserve authentication', async (t) => {
  const requests = [];
  const server = createServer(async (req, res) => {
    let raw = ''; for await (const chunk of req) raw += chunk;
    requests.push({ path: req.url, headers: req.headers, body: raw ? JSON.parse(raw) : null });
    res.setHeader('content-type', 'application/json');
    if (req.url.endsWith('/models')) res.end(JSON.stringify({ data: [{ id: 'test-rwkv' }] }));
    else res.end(JSON.stringify({ choices: [{ message: { content: '{"ok":true}' } }] }));
  });
  await new Promise((done) => server.listen(0, '127.0.0.1', done));
  t.after(async () => { server.closeAllConnections(); await new Promise((done) => server.close(done)); });
  const config = { baseUrl: `http://127.0.0.1:${server.address().port}/v1/models`, protocol: 'python',
    apiKey: 'private-token', headers: { 'CF-Access-Client-Id': 'gateway-id' }, model: 'test-rwkv', maxTokens: 2048, temperature: 0.4 };
  const discovered = await listModels(config);
  assert.deepEqual(discovered.models, ['test-rwkv']);
  assert.match(discovered.summary, /生成能力需单独测试/);
  const result = await new Provider(config, new Pool(1)).generate('测试', {}, new AbortController().signal);
  assert.equal(result.ok, true);
  assert.deepEqual(requests.map((item) => item.path), ['/v1/models', '/v1/chat/completions']);
  assert.equal(requests[1].body.contents.length, 1);
  assert.equal(requests[1].body.messages, undefined);
  assert.equal(requests[1].body.password, 'private-token');
  assert.equal(requests[1].body.max_tokens, 2048);
  assert.equal(requests[1].body.temperature, 0.4);
  assert.equal(requests[1].headers.authorization, 'Bearer private-token');
  assert.equal(requests[0].headers['cf-access-client-id'], 'gateway-id');
});

test('model discovery reports authentication failure without returning credentials', async (t) => {
  const server = createServer((_req, res) => { res.writeHead(403); res.end('private-token'); });
  await new Promise((done) => server.listen(0, '127.0.0.1', done));
  t.after(async () => { server.closeAllConnections(); await new Promise((done) => server.close(done)); });
  await assert.rejects(listModels({ baseUrl: `http://127.0.0.1:${server.address().port}`, apiKey: 'private-token' }), (error) => /403/.test(error.message) && !error.message.includes('private-token'));
});

test('blank model discovers Qwen once for concurrent experts and applies its non-thinking setting', async (t) => {
  let discovery = 0;
  const requests = [];
  const server = createServer(async (req, res) => {
    res.setHeader('content-type', 'application/json');
    if (req.url === '/v1/models') {
      discovery++;
      res.end(JSON.stringify({ data: [{ id: 'other-model' }, { id: 'Qwen3-32B' }] }));
      return;
    }
    let raw = ''; for await (const chunk of req) raw += chunk;
    requests.push(JSON.parse(raw));
    res.end(JSON.stringify({ choices: [{ message: { content: '{"ok":true}' } }] }));
  });
  await new Promise((done) => server.listen(0, '127.0.0.1', done));
  t.after(async () => { server.closeAllConnections(); await new Promise((done) => server.close(done)); });
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  const target = connection({ baseUrl, protocol: 'chat' });
  assert.equal(target.apiKey, process.env.FOREMAN_PASSWORD || '', 'local credentials must never become defaults for unrelated servers');
  const provider = new Provider({ baseUrl, model: '', protocol: 'chat', enableThinking: false }, new Pool(2));
  await Promise.all([1, 2, 3].map(() => provider.generate('测试', {}, new AbortController().signal)));
  assert.equal(discovery, 1);
  assert.equal(requests.length, 3);
  assert.ok(requests.every((body) => body.model === 'Qwen3-32B' && body.chat_template_kwargs.enable_thinking === false));
});

test('bounded evidence tools read actual snapshot lines and never access arbitrary paths or the web', () => {
  const snapshot = { files: { '合同.txt': { content: '项目\n预算 24680 元\n交付 12 月' }, 'hidden.txt': { content: 'out-of-scope' } } };
  const evidence = [{ id: 'E1', path: '合同.txt' }];
  assert.equal(analysisTool('read_file', { evidenceId: 'E1', startLine: 2, lineCount: 1 }, snapshot, evidence).text, '预算 24680 元');
  assert.equal(analysisTool('search_text', { query: '24680' }, snapshot, evidence).matches[0].line, 2);
  assert.throws(() => analysisTool('read_file', { evidenceId: 'hidden.txt', path: '../other.txt' }, snapshot, evidence), /不存在/);
  assert.throws(() => analysisTool('web_search', { query: 'x' }, snapshot, evidence), /不提供联网搜索/);
  assert.equal(calculate('(24680 - 4321) * 2').result, 40718);
  for (const expression of ['1/0', 'process.exit()', '2**10', '', '('.repeat(101)]) assert.throws(() => calculate(expression));
});
