import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { loopbackFetch } from '../src/loopback-http.mjs';
import { listModels } from '../src/connection.mjs';
import { Provider } from '../src/provider.mjs';
import { Pool } from '../src/runtime.mjs';

async function serve(t, handler) {
  const server = createServer(handler);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  return `http://127.0.0.1:${server.address().port}`;
}

test('loopback HTTP preserves JSON and UTF-8 SSE while discovery and inference bypass global proxies', async t => {
  const baseUrl = await serve(t, async (req, res) => {
    let raw = '';
    for await (const chunk of req) raw += chunk;
    if (req.url === '/v1/models') { res.end(JSON.stringify({ data: [{ id: '本地模型' }] })); return; }
    assert.equal(JSON.parse(raw).messages[1].content.includes('你好'), true);
    res.setHeader('Content-Type', 'text/event-stream');
    const data = Buffer.from(`data: ${JSON.stringify({ choices: [{ delta: { content: '{"answer":"中文"}' }, finish_reason: 'stop' }] })}\n\ndata: [DONE]\n\n`);
    res.write(data.subarray(0, 72));
    setTimeout(() => res.end(data.subarray(72)), 20);
  });
  t.mock.method(globalThis, 'fetch', () => { throw new Error('system proxy rejected loopback'); });
  const config = { baseUrl, inferenceMode: 'local', protocol: 'chat' };
  assert.deepEqual((await listModels(config)).models, ['本地模型']);
  const result = await new Provider(config, new Pool(1)).generate('你好', {}, new AbortController().signal);
  assert.equal(result.answer, '中文');
  assert.equal(globalThis.fetch.mock.callCount(), 0);
});

test('loopback transport rejects nonlocal targets and redirects', async t => {
  for (const url of ['https://example.org', 'http://127.0.0.1@example.org', 'file:///tmp/a']) {
    assert.throws(() => loopbackFetch(url), /回环地址/);
  }
  const baseUrl = await serve(t, (_req, res) => { res.writeHead(307, { Location: 'https://example.org' }); res.end(); });
  await assert.rejects(loopbackFetch(baseUrl), /重定向/);
});

test('loopback cancellation covers headers and stalled streamed bodies', async t => {
  const baseUrl = await serve(t, (req, res) => {
    if (req.url === '/stream') { res.writeHead(200); res.write('first'); }
  });
  const beforeHeaders = new AbortController();
  const pending = loopbackFetch(baseUrl, { signal: beforeHeaders.signal });
  beforeHeaders.abort();
  await assert.rejects(pending, { name: 'AbortError' });
  const controller = new AbortController();
  const response = await loopbackFetch(`${baseUrl}/stream`, { signal: controller.signal });
  const body = response.text();
  controller.abort();
  await assert.rejects(body, { name: 'AbortError' });
});
