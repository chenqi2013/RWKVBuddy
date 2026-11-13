import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const serviceRoot = dirname(dirname(fileURLToPath(import.meta.url)));
export const abortError = () => new DOMException('任务已取消', 'AbortError');
export function checkAbort(signal) { if (signal?.aborted) throw abortError(); }

export class Pool {
  constructor(limit) { this.limit = limit; this.active = 0; this.queue = []; }
  async use(fn, signal) {
    checkAbort(signal);
    await new Promise((resolve, reject) => {
      const item = { resolve, reject, signal, abort: null };
      item.abort = () => {
        const index = this.queue.indexOf(item);
        if (index >= 0) this.queue.splice(index, 1);
        reject(abortError());
      };
      signal?.addEventListener('abort', item.abort, { once: true });
      this.queue.push(item);
      this.drain();
    });
    try { checkAbort(signal); return await fn(); }
    finally { this.active--; this.drain(); }
  }
  drain() {
    while (this.active < this.limit && this.queue.length) {
      const item = this.queue.shift();
      item.signal?.removeEventListener('abort', item.abort);
      if (item.signal?.aborted) { item.reject(abortError()); continue; }
      this.active++;
      item.resolve();
    }
  }
}

export function luaExecutable() {
  const bundled = join(serviceRoot, 'runtime', process.platform === 'win32' ? 'lua.exe' : 'lua');
  return process.env.RWKVBUDDY_LUA_PATH || process.env.FOREMAN_LUA_PATH ||
    (existsSync(bundled) ? bundled : 'lua');
}

// Only application-generated numeric verification scripts are passed to this tool.
// No model-generated commands or shell interpolation are accepted.
export function runLua(code, { signal, timeout = 8000, onStart = () => {} } = {}) {
  checkAbort(signal);
  return new Promise((resolve, reject) => {
    const child = spawn(luaExecutable(), ['-'], {
      windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'],
    });
    let stdout = '';
    let stderr = '';
    let reason;
    const stop = (error) => { reason ??= error; child.kill(); };
    const abort = () => stop(abortError());
    const timer = setTimeout(() => stop(new Error('Lua 运算超过 8 秒')), timeout);
    signal?.addEventListener('abort', abort, { once: true });
    if (signal?.aborted) abort();
    child.on('spawn', () => onStart(child.pid));
    child.stdout.on('data', (data) => {
      stdout += data;
      if (stdout.length > 1024 * 1024) stop(new Error('工具输出超过限制'));
    });
    child.stderr.on('data', (data) => { stderr = (stderr + data).slice(-4000); });
    child.stdin.on('error', () => {});
    child.on('error', (error) => { reason = new Error(error.code === 'ENOENT'
      ? '找不到 Lua，请安装 Lua 或使用附带运行时的发布包' : error.message); });
    child.on('close', (exit) => {
      clearTimeout(timer);
      signal?.removeEventListener('abort', abort);
      if (reason) reject(reason);
      else if (exit !== 0) reject(new Error(stderr || `Lua 退出码 ${exit}`));
      else resolve(stdout.trim());
    });
    child.stdin.end(code);
  });
}
