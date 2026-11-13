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
