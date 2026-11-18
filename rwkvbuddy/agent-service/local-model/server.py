"""Loopback-only RWKV-7 service. No model download or network access at runtime."""

import argparse
import json
import math
import os
from pathlib import Path
from queue import Empty, Full, Queue
import re
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


MODEL_ID = 'rwkv-g1m-1b-temp-6629-ctx65536'


def prompt_from_request(body):
    contents = body.get('contents')
    if contents is not None:
        if not isinstance(contents, list) or len(contents) != 1 or not isinstance(contents[0], str):
            raise ValueError('contents must contain exactly one prompt')
        return contents[0]
    messages = body.get('messages')
    if not isinstance(messages, list) or not messages:
        raise ValueError('Provide messages or contents')
    turns = []
    for message in messages:
        if not isinstance(message, dict) or message.get('role') not in ('system', 'user', 'assistant'):
            raise ValueError('Only system, user and assistant text messages are supported')
        content = message.get('content')
        if not isinstance(content, str):
            raise ValueError('Message content must be text')
        content = re.sub(r'\n{2,}', '\n', content.replace('\r\n', '\n')).strip()
        turns.append(f"{message['role'].title()}: {content}")
    return '\n\n'.join(turns) + '\n\nAssistant:'


class RWKVBackend:
    def __init__(self, path, strategy, threads, context_limit):
        # Select the v7 implementation before importing rwkv.model. No compiler
        # or CUDA extension is needed for the portable CPU path.
        os.environ['RWKV_V7_ON'] = '1'
        os.environ['RWKV_CUDA_ON'] = '0'
        os.environ.pop('RWKV_DE_VERSION', None)
        import torch
        from rwkv.model import RWKV
        from rwkv.utils import PIPELINE

        self.torch = torch
        torch.set_num_threads(threads)
        self.model = RWKV(model=str(path.with_suffix('')), strategy=strategy)
        self.pipeline = PIPELINE(self.model, 'rwkv_vocab_v20230424')
        self.context_limit = context_limit

    def prepare(self, prompt, max_tokens):
        tokens = self.pipeline.encode(prompt)
        if len(tokens) + max_tokens > self.context_limit:
            raise ValueError(f'Input {len(tokens)} + output {max_tokens} exceeds local context budget '
                             f'{self.context_limit}; shorten the input or raise --context-limit. Nothing was truncated.')
        return tokens

    def generate(self, tokens, max_tokens, temperature, cancelled):
        state = None
        logits = None
        with self.torch.inference_mode():
            # Chunking limits prefill memory; every request gets an independent
            # recurrent state, even after failure, cancellation or another user.
            for offset in range(0, len(tokens), 64):
                if cancelled.is_set():
                    return
                logits, state = self.model.forward(tokens[offset:offset + 64], state)
            pending = []
            for _ in range(max_tokens):
                if cancelled.is_set():
                    return
                if not self.torch.isfinite(logits).all():
                    raise RuntimeError('Non-finite logits; try --strategy "cpu fp32"')
                token = (int(self.torch.argmax(logits).item()) if temperature == 0 else
                         self.pipeline.sample_logits(logits, temperature=temperature, top_p=0.7, top_k=50))
                if token == 0:
                    return
                pending.append(token)
                piece = self.pipeline.decode(pending)
                if '\ufffd' not in piece:
                    yield piece
                    pending.clear()
                logits, state = self.model.forward([token], state)
            if pending:
                raise RuntimeError('Generation ended inside a UTF-8 character')
            # A separate sentinel ensures callers never accept token-truncated
            # JSON as a successful completed response.
            yield None


class LocalServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, backend, model_id=MODEL_ID):
        self.backend = backend
        self.model_id = model_id
        self.inference_lock = threading.Lock()
        super().__init__(address, Handler)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        # Never log prompts or model text, which may contain document content.
        pass

    def json_response(self, status, value):
        data = json.dumps(value, ensure_ascii=False).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == '/v1/models':
            self.json_response(200, {'object': 'list', 'data': [
                {'id': self.server.model_id, 'object': 'model', 'owned_by': 'local'}]})
        elif self.path == '/health':
            self.json_response(200, {'ok': True, 'model': self.server.model_id, 'local': True})
        else:
            self.json_response(404, {'error': {'message': 'Unknown endpoint'}})

    def do_POST(self):
        if self.path != '/v1/chat/completions':
            self.json_response(404, {'error': {'message': 'Unknown endpoint'}})
            return
        # No CORS. Reject browser-originated requests to the unauthenticated
        # loopback service, including requests from a hostile public webpage.
        if self.headers.get('Transfer-Encoding'):
            self.json_response(403, {'error': {'message': 'Browser origins and transfer encoding are unsupported'}})
            return
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if not 0 < size <= 1024 * 1024:
                raise ValueError('Request must be between 1 byte and 1 MB')
            self.connection.settimeout(15)
            raw_body = self.rfile.read(size)
            # Drain the bounded request body before refusing a browser request.
            # Closing a Windows socket with unread data can reset the connection
            # before the caller receives the HTTP error.
            if self.headers.get('Origin'):
                self.json_response(403, {'error': {'message': 'Browser origins are unsupported'}})
                return
            body = json.loads(raw_body)
            if not isinstance(body, dict):
                raise ValueError('Request must be a JSON object')
            if body.get('model', self.server.model_id) != self.server.model_id:
                raise ValueError('Requested model is not loaded')
            max_tokens = body.get('max_tokens', 1024)
            temperature = body.get('temperature', 0.2)
            if type(max_tokens) is not int or not 1 <= max_tokens <= 8192:
                raise ValueError('max_tokens must be an integer between 1 and 8192')
            if type(temperature) not in (int, float) or not math.isfinite(temperature) or not 0 <= temperature <= 2:
                raise ValueError('temperature must be between 0 and 2')
            prompt = prompt_from_request(body)
            if not prompt.strip():
                raise ValueError('Prompt is empty')
            tokens = self.server.backend.prepare(prompt, max_tokens)
        except (ValueError, TypeError, OSError) as error:
            self.json_response(400, {'error': {'message': str(error)}})
            return
        if not self.server.inference_lock.acquire(blocking=False):
            self.json_response(429, {'error': {'message': 'Local model is busy; use concurrency=1'}})
            return

        cancelled = threading.Event()
        output = Queue(maxsize=32)

        def put(value):
            while not cancelled.is_set():
                try:
                    output.put(value, timeout=0.1)
                    return
                except Full:
                    continue

        def infer():
            try:
                reason = 'stop'
                for piece in self.server.backend.generate(tokens, max_tokens, temperature, cancelled):
                    if piece is None:
                        reason = 'length'
                    else:
                        put(('text', piece))
                put(('done', reason))
            except Exception:
                put(('error', 'Local inference failed; inspect runtime/model compatibility and available memory'))
            finally:
                self.server.inference_lock.release()

        threading.Thread(target=infer, daemon=True).start()
        streaming = body.get('stream', False) is True
        try:
            if streaming:
                self.send_response(200)
                self.send_header('Content-Type', 'text/event-stream; charset=utf-8')
                self.send_header('Cache-Control', 'no-cache')
                self.end_headers()
            text = ''
            while True:
                try:
                    kind, value = output.get(timeout=0.5)
                except Empty:
                    if streaming:
                        self.wfile.write(b': prefill-or-generation\n\n')
                        self.wfile.flush()
                    continue
                if kind == 'error':
                    if streaming:
                        self.sse({'error': {'message': value}})
                    else:
                        self.json_response(500, {'error': {'message': value}})
                    return
                if kind == 'text':
                    if streaming:
                        self.sse({'choices': [{'index': 0, 'delta': {'content': value}}]})
                    else:
                        text += value
                if kind == 'done':
                    if streaming:
                        self.sse({'choices': [{'index': 0, 'delta': {}, 'finish_reason': value}]})
                        self.wfile.write(b'data: [DONE]\n\n')
                        self.wfile.flush()
                    else:
                        self.json_response(200, {'model': self.server.model_id, 'choices': [
                            {'index': 0, 'message': {'role': 'assistant', 'content': text}, 'finish_reason': value}]})
                    return
        except (ConnectionError, TimeoutError):
            pass
        finally:
            cancelled.set()

    def sse(self, value):
        self.wfile.write(('data: ' + json.dumps(value, ensure_ascii=False) + '\n\n').encode('utf-8'))
        self.wfile.flush()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', type=Path, required=True)
    parser.add_argument('--port', type=int, default=8099)
    parser.add_argument('--strategy', choices=['cpu fp32', 'cpu fp16', 'cpu bf16', 'cuda fp16', 'cuda fp32', 'cuda bf16'], default='cpu fp32')
    parser.add_argument('--threads', type=int, default=4)
    parser.add_argument('--context-limit', type=int, default=8192)
    args = parser.parse_args()
    if not args.model.is_file() or args.model.suffix != '.pth':
        parser.error('--model must point to an existing .pth file')
    if not 1 <= args.threads <= 128 or not 256 <= args.context_limit <= 65536 or not 1 <= args.port <= 65535:
        parser.error('Invalid threads, context limit or port')
    print('Loading local RWKV-7 weights; CPU startup can take several minutes.', flush=True)
    backend = RWKVBackend(args.model.resolve(), args.strategy, args.threads, args.context_limit)
    server = LocalServer(('127.0.0.1', args.port), backend, args.model.stem)
    print(f'Ready: http://127.0.0.1:{args.port}/v1 ; model={server.model_id}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
