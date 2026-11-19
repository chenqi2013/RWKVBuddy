import test from 'node:test';
import assert from 'node:assert/strict';
import { modelProgress } from '../src/model-progress.mjs';

test('public progress and answer are readable before JSON completes, including split escapes', () => {
  assert.deepEqual(modelProgress('{"progress":"核对 README","answer":"技术栈：Flutter\\nDart\\u4e'), {
    progress: '核对 README', answerPreview: '技术栈：Flutter\nDart', pendingTool: '',
  });
  assert.equal(modelProgress('{"answer":"引号：\\"例子\\"，路径 C:\\\\data"}').answerPreview, '引号："例子"，路径 C:\\data');
  assert.equal(modelProgress('{"progress":"正在检索","tool":"search_text","arguments":').pendingTool, 'search_text');
  assert.equal(modelProgress('{"progress":"准备读取","tool":{"name":"read_file","arguments":').pendingTool, 'read_file');
});

test('supports RWKV submit wrapper and fenced responses', () => {
  assert.equal(modelProgress('```json\n{"name":"submit","arguments":{"answer":{"progress":"核对资料","answer":"正文').answerPreview, '正文');
});

test('does not mistake reasoning, file contents or embedded keys for public progress', () => {
  for (const text of [
    '<think>private reasoning</think>{"answer":"后续"}',
    '{"reasoning_content":"private reasoning","files":[{"content":"{\\"answer\\":\\"文件内容\\"}"}]}',
    '{"other":{"progress":"nested private text"}}',
  ]) assert.deepEqual(modelProgress(text), { progress: '', answerPreview: '', pendingTool: '' });
});
