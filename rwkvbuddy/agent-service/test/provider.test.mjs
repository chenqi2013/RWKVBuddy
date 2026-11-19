import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { Provider } from '../src/provider.mjs';
import { Pool } from '../src/runtime.mjs';

async function server(t, handler) {
  const instance = createServer(handler);
  await new Promise((done) => instance.listen(0, '127.0.0.1', done));
  t.after(async () => { instance.closeAllConnections(); await new Promise((done) => instance.close(done)); });
  return `http://127.0.0.1:${instance.address().port}/v1`;
}
async function body(request) {
  let text = '';
  for await (const chunk of request) text += chunk;
  return JSON.parse(text);
}
test('real HTTP RWKV adapter parses split UTF-8 SSE and an unterminated last line', async (t) => {
  let path; let input;
  const baseUrl = await server(t, async (request, response) => {
    path = request.url; input = await body(request);
    response.writeHead(200, { 'Content-Type': 'text/event-stream' });
    const output = JSON.stringify({ name: 'submit', arguments: { answer: { summary: '中文专家', findings: [{ text: '来源可查', evidenceIds: ['E1'] }] } } });
    const bytes = Buffer.from(`data: ${JSON.stringify({ choices: [{ index: 0, text: output }] })}`);
    const chinese = bytes.indexOf(Buffer.from('中文'));
    response.write(bytes.subarray(0, chinese + 1));
    setImmediate(() => response.end(bytes.subarray(chinese + 1)));
  });
  const provider = new Provider({ baseUrl, protocol: 'rwkv', model: 'test-model' }, new Pool(2));
  const result = await provider.generate('分析', {}, new AbortController().signal);
  assert.equal(result.summary, '中文专家');
  assert.equal(path, '/v1/batch/completions');
  assert.equal(input.contents.length, 1);
  assert.equal(input.model, 'test-model');
});
test('chat protocol uses independent messages and rejects non-JSON model output', async (t) => {
  let path; let input;
  const baseUrl = await server(t, async (request, response) => {
    path = request.url; input = await body(request);
    response.writeHead(200, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify({ choices: [{ message: { content: 'unstructured answer' } }] }));
  });
  const provider = new Provider({ baseUrl, protocol: 'chat', model: 'test-model' }, new Pool(1));
  await assert.rejects(provider.generate('分析', {}, new AbortController().signal), /有效 JSON/);
  assert.equal(path, '/v1/chat/completions');
  assert.equal(input.messages.length, 2);
  assert.ok(!input.contents);
  assert.equal(input.response_format, undefined);
});
test('local GGUF chat requests constrained JSON and disables thinking without legacy raw prompts', async (t) => {
  let input;
  const baseUrl = await server(t, async (request, response) => {
    input = await body(request);
    response.writeHead(200, { 'Content-Type': 'text/event-stream' });
    response.write(`data: ${JSON.stringify({ choices: [{ delta: { reasoning_content: 'private reasoning' } }] })}\n\n`);
    response.end(`data: ${JSON.stringify({ choices: [{ delta: { content: '{"ok":true}' }, finish_reason: 'stop' }] })}\n\ndata: [DONE]\n\n`);
  });
  const provider = new Provider({ baseUrl, inferenceMode: 'local', protocol: 'chat',
    model: 'rwkv7-g1l-1.5b-Q4_K_M', enableThinking: false }, new Pool(1));
  const output = [];
  const result = await provider.generate('测试', {}, new AbortController().signal, (_length, text) => output.push(text));
  assert.equal(result.ok, true);
  assert.deepEqual(input.response_format, { type: 'json_object' });
  assert.equal(input.chat_template_kwargs.enable_thinking, false);
  assert.equal(input.messages.length, 2);
  assert.equal(input.contents, undefined);
  assert.ok(output.every((text) => !text.includes('private reasoning')));
});
test('cancelling an active HTTP stream rejects and releases model slot', async (t) => {
  let ready;
  const connected = new Promise((done) => { ready = done; });
  const baseUrl = await server(t, async (request, response) => {
    await body(request);
    response.writeHead(200, { 'Content-Type': 'text/event-stream' });
    response.write(': heartbeat\n\n'); ready();
  });
  const pool = new Pool(1);
  const provider = new Provider({ baseUrl, model: 'test-model' }, pool);
  const controller = new AbortController();
  const pending = provider.generate('分析', {}, controller.signal);
  await connected;
  controller.abort();
  await assert.rejects(pending, { name: 'AbortError' });
  assert.equal(pool.active, 0);
});

test('token-truncated streamed responses are reported separately from malformed JSON', async (t) => {
  const baseUrl = await server(t, async (request, response) => {
    await body(request);
    response.writeHead(200, { 'Content-Type': 'text/event-stream' });
    response.write(`data: ${JSON.stringify({ choices: [{ delta: { content: '{"answer":"未完成' } }] })}\n\n`);
    response.end(`data: ${JSON.stringify({ choices: [{ delta: {}, finish_reason: 'length' }] })}\n\ndata: [DONE]\n\n`);
  });
  const provider = new Provider({ baseUrl, protocol: 'chat', model: 'test-model' }, new Pool(1));
  await assert.rejects(provider.generate('分析', {}, new AbortController().signal), (error) => error.code === 'MODEL_OUTPUT_TRUNCATED' && /截断/.test(error.message));
});

test('recovery output allowance overrides request tokens without changing saved connection', async (t) => {
  const limits = [];
  const baseUrl = await server(t, async (request, response) => {
    const input = await body(request);
    limits.push(input.max_tokens);
    response.writeHead(200, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify({ choices: [{ message: { content: '{"answer":"完成"}' }, finish_reason: 'stop' }] }));
  });
  const config = { baseUrl, protocol: 'chat', model: 'test-model', maxTokens: 4096 };
  const provider = new Provider(config, new Pool(1));
  await provider.generate('分析', {}, new AbortController().signal);
  await provider.generate('重试', {}, new AbortController().signal, () => {}, { maxTokens: 8192 });
  assert.deepEqual(limits, [4096, 8192]);
  assert.equal(config.maxTokens, 4096);
});

test('chat streams public content before request completion and ignores reasoning deltas', async (t) => {
  let release;
  const gate = new Promise((done) => { release = done; });
  t.after(() => release());
  const baseUrl = await server(t, async (request, response) => {
    await body(request);
    response.writeHead(200, { 'Content-Type': 'text/event-stream' });
    response.write(`data: ${JSON.stringify({ choices: [{ delta: { reasoning_content: 'private reasoning' } }] })}\n\n`);
    response.write(`data: ${JSON.stringify({ choices: [{ delta: { content: '{"progress":"核对资料","answer":"正在生成' } }] })}\n\n`);
    await gate;
    response.end(`data: ${JSON.stringify({ choices: [{ delta: { content: '正文"}' }, finish_reason: 'stop' }] })}\n\ndata: [DONE]\n\n`);
  });
  const phases = [];
  let live;
  const received = new Promise((done) => { live = done; });
  const provider = new Provider({ baseUrl, protocol: 'chat', model: 'test-model' }, new Pool(1));
  const pending = provider.generate('分析', {}, new AbortController().signal, (length, text, status) => {
    phases.push(status.phase);
    assert.ok(!text.includes('private reasoning'));
    if (length > 0) live(text);
  });
  assert.match(await received, /正在生成/);
  release();
  const result = await pending;
  assert.equal(result.answer, '正在生成正文');
  assert.deepEqual(phases.slice(0, 4), ['queued', 'requesting', 'waiting', 'streaming']);
});
