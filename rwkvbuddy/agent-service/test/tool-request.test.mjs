import test from 'node:test';
import assert from 'node:assert/strict';
import { toolRequest } from '../src/tool-request.mjs';

test('normalizes flat and nested tool requests without modifying raw model responses', () => {
  const args = { path: 'README.md', startLine: 1, lineCount: 100 };
  for (const response of [
    { tool: 'read_file', arguments: args },
    { tool: { name: 'read_file', arguments: args } },
    { tool: 'read_file', arguments: JSON.stringify(args) },
    { tool: { name: 'read_file', arguments: JSON.stringify(args) } },
  ]) {
    const original = structuredClone(response);
    assert.deepEqual(toolRequest(response), { name: 'read_file', arguments: args });
    assert.deepEqual(response, original);
  }
});

test('does not execute or guess malformed argument strings or invalid tool names', () => {
  const raw = '{path: "README.md"}';
  assert.deepEqual(toolRequest({ tool: { name: 'read_file', arguments: raw } }), { name: 'read_file', arguments: raw });
  assert.equal(toolRequest({ tool: { arguments: {} } }).name, 'tool.invalid');
});
