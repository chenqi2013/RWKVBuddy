import { defaultConnection } from './defaults.mjs';

export function connection(config = {}) {
  const url = new URL((config.baseUrl || process.env.FOREMAN_BASE_URL || defaultConnection.baseUrl).trim());
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.search || url.hash) {
    throw new Error('服务地址须为 HTTP(S)，不含查询参数、账号或密码');
  }
  const protocol = config.protocol || defaultConnection.protocol;
  if (!['rwkv', 'python', 'chat'].includes(protocol)) throw new Error('请选择有效服务协议');
  let path = url.pathname.replace(/\/+$/, '').replace(/\/(?:models|batch\/completions|chat\/completions)$/, '');
  if (!path.endsWith('/v1')) path += '/v1';
  url.pathname = path;
  const baseUrl = url.toString().replace(/\/$/, '');
  const headers = { 'Content-Type': 'application/json' };
  for (const [key, value] of Object.entries(config.headers || {})) {
    if (!/^[!#$%&'*+.^_`|~0-9A-Za-z-]+$/.test(key) || /[\r\n]/.test(String(value)) ||
        /^(host|content-length|connection|transfer-encoding)$/i.test(key)) throw new Error('自定义请求头格式无效');
    headers[key] = String(value);
  }
  const apiKey = config.apiKey || process.env.FOREMAN_PASSWORD ||
    (!config.baseUrl && !process.env.FOREMAN_BASE_URL ? defaultConnection.apiKey : '');
  if (apiKey) headers.Authorization = `Bearer ${apiKey}`;
  const accessId = config.accessId || process.env.FOREMAN_CF_ACCESS_CLIENT_ID;
  const accessSecret = config.accessSecret || process.env.FOREMAN_CF_ACCESS_CLIENT_SECRET;
  if (accessId) headers['CF-Access-Client-Id'] = accessId;
  if (accessSecret) headers['CF-Access-Client-Secret'] = accessSecret;
  return { baseUrl, protocol, headers, apiKey, endpoint: `${baseUrl}/${protocol === 'rwkv' ? 'batch/completions' : 'chat/completions'}` };
}
export async function listModels(config, signal) {
  const target = connection(config);
  const start = Date.now();
  let response;
  try {
    response = await fetch(`${target.baseUrl}/models`, { headers: target.headers,
      signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(15000)]) : AbortSignal.timeout(15000) });
  } catch { throw new Error('连接失败或超过 15 秒，请检查地址、网络和代理配置'); }
  if (!response.ok) {
    await response.body?.cancel();
    throw new Error(`HTTP ${response.status}：${response.status === 401 || response.status === 403 ? '服务拒绝访问，请检查令牌和请求头' : '无法获取模型列表'}`);
  }
  const reader = response.body.getReader();
  let size = 0;
  const chunks = [];
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 1024 * 1024) throw new Error('模型列表响应过大');
      chunks.push(Buffer.from(value));
    }
  } finally { await reader.cancel().catch(() => {}); }
  let parsed;
  try { parsed = JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { throw new Error('模型列表不是有效 JSON'); }
  const rows = Array.isArray(parsed) ? parsed : parsed.data || parsed.models;
  if (!Array.isArray(rows)) throw new Error('服务未返回兼容的模型列表');
  const models = [...new Set(rows.map((item) => typeof item === 'string' ? item : item.id || item.name)
    .filter((value) => typeof value === 'string' && value.length <= 300))].slice(0, 200);
  return { models, latencyMs: Date.now() - start, baseUrl: target.baseUrl,
    endpoint: target.endpoint, summary: `已连接，发现 ${models.length} 个模型（模型列表可达，生成能力需单独测试）` };
}
