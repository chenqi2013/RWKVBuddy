import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync, renameSync } from 'node:fs';
import { open, realpath, stat } from 'node:fs/promises';
import { basename, extname, join } from 'node:path';
import { serviceRoot, Pool, checkAbort, abortError } from './runtime.mjs';

export function runtimePath(root = serviceRoot, platform = process.platform, arch = process.arch) {
  if (!['win32', 'darwin'].includes(platform) || !['x64', 'arm64'].includes(arch)) throw new Error('本地模型支持 Windows/macOS x64 和 ARM64');
  return join(root, 'runtime', 'llama', `${platform === 'win32' ? 'windows' : 'macos'}-${arch}`, platform === 'win32' ? 'rwkvbuddy-inference.exe' : 'rwkvbuddy-inference');
}

export async function inspectGGUF(path) {
  if (typeof path !== 'string' || !path || extname(path).toLowerCase() !== '.gguf') throw new Error('请选择 .gguf 模型文件');
  const absolute = await realpath(path);
  const info = await stat(absolute);
  if (!info.isFile() || info.size < 24) throw new Error('GGUF 文件不完整');
  const file = await open(absolute, 'r');
  try {
    const header = Buffer.alloc(24);
    await file.read(header, 0, 24, 0);
    if (header.toString('ascii', 0, 4) !== 'GGUF' || ![2, 3].includes(header.readUInt32LE(4)) || header.readBigUInt64LE(8) === 0n) throw new Error('不是有效的 GGUF v2/v3 模型文件');
  } finally { await file.close(); }
  return { path: absolute, name: basename(absolute), model: basename(absolute, extname(absolute)), bytes: info.size };
}

export class LocalModels {
  constructor(directory, emit, options = {}) {
    this.file = join(directory, 'local-models.json');
    this.emit = emit;
    this.executable = options.executable || runtimePath();
    this.launch = options.launch || ((args, opts) => spawn(this.executable, args, opts));
    this.timeout = options.timeout ?? 180000;
    this.cancelTimeout = options.cancelTimeout ?? 5000;
    this.pool = new Pool(1);
    this.models = [];
    this.state = { status: 'idle', modelId: '', message: '尚未加载模型' };
    try {
      const saved = JSON.parse(readFileSync(this.file, 'utf8'));
      if (Array.isArray(saved)) this.models = saved.filter(m => typeof m.id === 'string' && typeof m.path === 'string' && typeof m.model === 'string' && typeof m.name === 'string' && Number.isFinite(m.bytes));
    } catch {}
  }
  snapshot() { return { models: this.models, state: this.state, runtimeAvailable: existsSync(this.executable) }; }
  publish() { this.emit(this.snapshot()); }
  save() {
    writeFileSync(`${this.file}.tmp`, JSON.stringify(this.models));
    renameSync(`${this.file}.tmp`, this.file);
    this.publish();
  }
  async import(path) {
    const data = await inspectGGUF(path);
    let model = this.models.find(m => process.platform === 'win32' ? m.path.toLowerCase() === data.path.toLowerCase() : m.path === data.path);
    if (!model) { model = { id: randomUUID(), ...data }; this.models.push(model); }
    else Object.assign(model, data);
    this.save();
    return model;
  }
  async remove(id) {
    if (!this.models.some(m => m.id === id)) throw new Error('模型记录不存在');
    if (this.state.modelId === id) await this.stop();
    this.models = this.models.filter(m => m.id !== id);
    this.save();
  }
  async stop() {
    const session = this.session;
    this.session = null;
    if (session) {
      for (const pending of session.pending.values()) pending.finish(new Error('模型已卸载或加载已取消'));
      if (session.child.exitCode === null && session.child.signalCode === null) {
        session.child.stdin.end(`${JSON.stringify({ type: 'shutdown' })}\n`);
        let timer;
        try {
          await Promise.race([session.exited, new Promise(resolve => { timer = setTimeout(() => { session.child.kill(); resolve(); }, 1500); })]);
        } finally { clearTimeout(timer); }
        if (session.child.exitCode === null && session.child.signalCode === null) session.child.kill('SIGKILL');
        await session.exited;
      }
    }
    this.state = { status: 'idle', modelId: '', message: '模型已卸载' };
    this.publish();
  }
  async close() { this.closed = true; await this.stop(); }
  fail(session, error) {
    session.error = error;
    for (const pending of session.pending.values()) pending.finish(error);
    if (this.session === session && this.state.status === 'ready') {
      this.state = { status: 'failed', modelId: this.state.modelId, message: error.message, detail: session.logs };
      this.publish();
    }
    session.child.kill();
  }
  request(session, command, signal, onEvent = () => {}) {
    checkAbort(signal);
    if (this.session !== session || session.error) return Promise.reject(session.error || new Error('模型已卸载'));
    const id = randomUUID();
    return new Promise((resolve, reject) => {
      let timer;
      let reason;
      const finish = (error, event) => {
        clearTimeout(timer);
        signal?.removeEventListener('abort', cancel);
        session.pending.delete(id);
        if (reason || error) reject(reason || error); else resolve(event);
      };
      const cancel = (error) => {
        if (reason) return;
        reason = error instanceof Error ? error : abortError();
        session.child.stdin.write(`${JSON.stringify({ type: 'cancel', id })}\n`);
        // Keep the slot occupied until native inference acknowledges cancellation.
        timer = setTimeout(() => this.fail(session, new Error('本地推理取消超时，模型已停止，请重新加载')), this.cancelTimeout);
      };
      session.pending.set(id, { finish, event: event => {
        if (event.type === 'error') finish(new Error(event.message || '本地推理失败'));
        else if (event.type === 'ready' || event.type === 'done') finish(null, event);
        else if (!reason) { try { onEvent(event); } catch (error) { cancel(error); } }
      } });
      signal?.addEventListener('abort', cancel, { once: true });
      const line = JSON.stringify({ ...command, id });
      if (Buffer.byteLength(line) > 2 * 1024 * 1024) { finish(new Error('模型输入超过大小限制')); return; }
      session.child.stdin.write(`${line}\n`, error => { if (error && session.pending.has(id)) this.fail(session, error); });
      if (signal?.aborted) cancel();
    });
  }
  async load(id) {
    if (this.loading || this.closed) throw new Error('模型正在加载或服务已关闭');
    this.loading = true;
    try { return await this.loadModel(id); }
    finally { this.loading = false; }
  }
  async loadModel(id) {
    const model = this.models.find(m => m.id === id);
    if (!model) throw new Error('请先导入 GGUF 文件');
    if (this.state.status === 'ready' && this.state.modelId === id) return this.profile(model);
    await inspectGGUF(model.path);
    if (!existsSync(this.executable)) throw new Error('安装包缺少原生推理运行时，请使用完整发布包');
    await this.stop();
    if (this.closed) throw new Error('服务已关闭');
    const child = this.launch([], { windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
    const session = { child, pending: new Map(), logs: '', error: null };
    this.session = session;
    this.state = { status: 'loading', modelId: id, transport: 'stdio', message: '正在原生加载 GGUF…' };
    this.publish();
    child.stderr.setEncoding('utf8');
    child.stderr.on('data', text => { session.logs = (session.logs + text).slice(-8000); });
    child.stdin.on('error', error => this.fail(session, error));
    child.stdout.setEncoding('utf8');
    let buffer = '';
    child.stdout.on('data', text => {
      buffer += text;
      if (buffer.length > 256000) { this.fail(session, new Error('原生推理输出超过大小限制')); return; }
      let newline;
      while ((newline = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0, newline).trim(); buffer = buffer.slice(newline + 1);
        if (!line) continue;
        try {
          const event = JSON.parse(line);
          if (event.type === 'progress' && this.session === session && this.state.status === 'loading') {
            const progress = Math.max(0, Math.min(100, Number(event.percent) || 0));
            this.state = { ...this.state, progress, message: progress < 100 ? `正在读取模型权重 ${progress}%…` : '正在初始化推理上下文…' };
            this.publish();
          } else session.pending.get(event.id)?.event(event);
        } catch { this.fail(session, new Error('原生推理返回无效数据')); return; }
      }
    });
    session.exited = new Promise(resolve => {
      child.once('error', error => { this.fail(session, error); resolve(); });
      child.once('close', (code, signal) => { this.fail(session, new Error(`原生推理进程退出（${code ?? signal}）`)); resolve(); });
    });
    try {
      const ready = await this.request(session, { type: 'load', path: model.path, context: 8192, threads: 4 }, AbortSignal.timeout(this.timeout));
      if (this.session !== session) throw new Error('加载已取消');
      this.state = { status: 'ready', modelId: id, transport: 'stdio', context: ready.context, message: '模型已加载，可以开始对话' };
      this.publish();
      return this.profile(model);
    } catch (error) {
      if (this.session === session) {
        await this.stop();
        this.state = { status: 'failed', modelId: id, message: error.name === 'AbortError' ? '原生模型加载超时' : error.message, detail: session.logs };
        this.publish();
      }
      throw error;
    }
  }
  profile(model) {
    return { id: `gguf-${model.id}`, name: model.model, inferenceMode: 'local', localModelId: model.id,
      baseUrl: '', model: model.model, protocol: 'native', transport: 'stdio', enableThinking: false, jsonOutput: true,
      concurrency: 1, maxTokens: 1024, temperature: 0.2, apiKey: '', headers: {} };
  }
  assertReady(config) {
    if (config?.localModelId && (this.state.status !== 'ready' || this.state.modelId !== config.localModelId || this.session?.error)) throw new Error('请在“模型服务 → 本地模型”中加载此模型后再使用');
  }
  async generate(config, body, signal, onChunk) {
    const session = this.session;
    return this.pool.use(async () => {
      this.assertReady(config);
      if (!session || this.session !== session) throw new Error('模型已切换，请重试');
      const done = await this.request(session, { type: 'generate', messages: body.messages, max_tokens: body.max_tokens, temperature: body.temperature }, signal, event => {
        if (event.type === 'delta') onChunk({ choices: [{ delta: { content: event.text } }], usage: { completion_tokens: event.completion_tokens } });
      });
      onChunk({ choices: [{ delta: {}, finish_reason: done.finish_reason }], usage: { prompt_tokens: done.prompt_tokens, completion_tokens: done.completion_tokens } });
    }, signal);
  }
}
