import { request as httpRequest } from 'node:http';
import { request as httpsRequest } from 'node:https';
import { Readable } from 'node:stream';

export function loopbackFetch(input, options = {}) {
  const url = new URL(input);
  if (!['http:', 'https:'].includes(url.protocol) || !['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname)
      || url.username || url.password) throw new Error('本地请求仅允许无凭据的 HTTP(S) 回环地址');
  const signal = options.signal;
  signal?.throwIfAborted();
  return new Promise((resolve, reject) => {
    const send = url.protocol === 'http:' ? httpRequest : httpsRequest;
    const request = send(url, { method: options.method || 'GET', headers: options.headers, agent: false });
    let incoming;
    const abort = () => {
      const reason = signal.reason || new DOMException('Request aborted', 'AbortError');
      request.destroy(reason);
      incoming?.destroy(reason);
    };
    const cleanup = () => signal?.removeEventListener('abort', abort);
    signal?.addEventListener('abort', abort, { once: true });
    if (signal?.aborted) abort();
    request.once('error', error => { cleanup(); reject(error); });
    request.once('response', response => {
      incoming = response;
      response.once('close', cleanup);
      const status = response.statusCode;
      if ([301, 302, 303, 307, 308].includes(status)) {
        response.destroy();
        reject(new Error('本地模型服务不允许 HTTP 重定向'));
        return;
      }
      const headers = new Headers();
      for (let index = 0; index < response.rawHeaders.length; index += 2) {
        headers.append(response.rawHeaders[index], response.rawHeaders[index + 1]);
      }
      const noBody = options.method === 'HEAD' || [204, 205, 304].includes(status);
      const body = noBody ? null : Readable.toWeb(response);
      if (noBody) response.resume();
      resolve(new Response(body, { status, headers }));
    });
    request.end(options.body);
  });
}
