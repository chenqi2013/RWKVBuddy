import test from 'node:test';
import assert from 'node:assert/strict';
import { GenerationMetrics } from '../src/generation-metrics.mjs';

test('speed excludes first-token waiting and uses token records rather than SSE chunk count', () => {
  let time = 10000;
  const metrics = new GenerationMetrics(() => time);
  assert.equal(metrics.update({ choices: [{ delta: { role: 'assistant', content: '' } }] }).tokensPerSecond, null);
  time = 15000;
  assert.equal(metrics.update({ choices: [{ token_ids: [1], delta: { content: 'one' } }] }).tokensPerSecond, null);
  time = 15200;
  const speed = metrics.update({ choices: [{ token_ids: [2, 3, 4], delta: { content: 'two three four' } }] });
  assert.equal(speed.completionTokens, 4);
  assert.equal(speed.source, 'tokens');
  assert.equal(speed.tokensPerSecond, 15);
  time = 15500;
  assert.equal(metrics.update({ usage: { completion_tokens: 4 }, choices: [] }).tokensPerSecond, 6);
});

test('fallback is labelled as estimated and final server usage replaces estimates without double counting', () => {
  let time = 0;
  const metrics = new GenerationMetrics(() => time);
  assert.equal(metrics.update({ choices: [{ delta: { content: '中文' } }] }).source, 'estimated');
  time = 1000;
  const estimated = metrics.update({ choices: [{ delta: { content: '测试' } }] });
  assert.equal(estimated.completionTokens, 4);
  assert.equal(estimated.tokensPerSecond, 2);
  const actual = metrics.update({ usage: { completion_tokens: 11 }, choices: [] });
  assert.equal(actual.source, 'usage');
  assert.equal(actual.tokensPerSecond, 10);
  assert.equal(actual.completionTokens, 11);
  assert.equal(metrics.update({ usage: { completion_tokens: 11 } }).completionTokens, 11);
});

test('logprobs take precedence over duplicate ids; non-streaming usage does not invent generation timing', () => {
  let time = 0;
  const metrics = new GenerationMetrics(() => time);
  metrics.update({ choices: [{ token_ids: [1, 2], logprobs: { content: [{ token: 'a' }, { token: 'b' }] } }] });
  time = 1000;
  const next = metrics.update({ choices: [{ logprobs: { content: [{ token: 'c' }] } }] });
  assert.equal(next.completionTokens, 3);
  assert.equal(next.tokensPerSecond, 1);
  const single = new GenerationMetrics(() => 1000).update({ usage: { completion_tokens: 50 }, choices: [{ message: { content: '完整回答' } }] });
  assert.equal(single.tokensPerSecond, null);
});
