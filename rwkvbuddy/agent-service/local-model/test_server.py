"""HTTP/stream/cancellation regression tests; deliberately do not evaluate weights."""

import http.client
import json
import threading
import unittest

from server import LocalServer, MODEL_ID, prompt_from_request


class Backend:
    def prepare(self, prompt, max_tokens):
        if 'oversized' in prompt:
            raise ValueError('Input exceeds local context budget; nothing was truncated')
        return prompt

    def generate(self, prompt, max_tokens, temperature, cancelled):
        yield '{"answer":"'
        yield '中文'
        yield '"}'
        if 'truncate' in prompt:
            yield None


class ServerTests(unittest.TestCase):
    def setUp(self):
        self.backend = Backend()
        self.server = LocalServer(('127.0.0.1', 0), self.backend)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.port = self.server.server_port

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(2)

    def request(self, path, data=None, headers=None):
        connection = http.client.HTTPConnection('127.0.0.1', self.port, timeout=5)
        self.addCleanup(connection.close)
        connection.request('GET' if data is None else 'POST', path,
                           body=None if data is None else json.dumps(data).encode(), headers=headers or {})
        response = connection.getresponse()
        return response.status, response.read().decode()

    def test_official_template_and_raw_prompt(self):
        self.assertEqual(prompt_from_request({'messages': [
            {'role': 'system', 'content': '工具'}, {'role': 'user', 'content': '你好'}]}),
            'System: 工具\n\nUser: 你好\n\nAssistant:')
        self.assertEqual(prompt_from_request({'contents': ['System: Tools:\n\nAssistant: ```json\n']}),
                         'System: Tools:\n\nAssistant: ```json\n')

    def test_discovery_and_nonstream_generation(self):
        status, text = self.request('/v1/models')
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(text)['data'][0]['id'], MODEL_ID)
        status, text = self.request('/v1/chat/completions', {'contents': ['test']})
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(text)['choices'][0]['message']['content'], '{"answer":"中文"}')

    def test_stream_and_truncation(self):
        status, text = self.request('/v1/chat/completions', {'contents': ['truncate'], 'stream': True})
        self.assertEqual(status, 200)
        events = [json.loads(line[6:]) for line in text.splitlines() if line.startswith('data: {')]
        self.assertEqual(events[-1]['choices'][0]['finish_reason'], 'length')
        self.assertTrue(text.endswith('data: [DONE]\n\n'))

    def test_invalid_inputs_and_context_are_rejected(self):
        for body in [{'contents': []}, {'contents': ['a', 'b']}, {'contents': ['a'], 'model': 'wrong'},
                     {'contents': ['oversized']}, {'contents': ['a'], 'max_tokens': -1},
                     {'contents': ['a'], 'temperature': float('nan')}, {'messages': [{'role': 'user', 'content': []}]}]:
            status, _ = self.request('/v1/chat/completions', body)
            self.assertEqual(status, 400, body)
        status, _ = self.request('/v1/chat/completions', {'contents': ['a']}, {'Origin': 'https://example.org'})
        self.assertEqual(status, 403)

    def test_cancellation_keeps_slot_until_model_stops(self):
        entered, cancelled_seen = threading.Event(), threading.Event()

        def generate(prompt, max_tokens, temperature, cancelled):
            entered.set()
            cancelled.wait(5)
            if cancelled.is_set():
                cancelled_seen.set()
            yield 'late'

        self.backend.generate = generate
        client = http.client.HTTPConnection('127.0.0.1', self.port, timeout=5)
        client.request('POST', '/v1/chat/completions', body=json.dumps({'contents': ['a'], 'stream': True}))
        response = client.getresponse()
        self.assertTrue(entered.wait(2))
        status, _ = self.request('/v1/chat/completions', {'contents': ['b']})
        self.assertEqual(status, 429)
        response.close()
        client.close()
        self.assertTrue(cancelled_seen.wait(4))
        self.assertTrue(self.server.inference_lock.acquire(timeout=2))
        self.server.inference_lock.release()


if __name__ == '__main__':
    unittest.main()
