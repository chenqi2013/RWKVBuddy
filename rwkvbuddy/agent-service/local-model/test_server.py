"""GGUF launcher contract tests; real inference is tested separately."""

from pathlib import Path
import tempfile
import unittest

from server import parser, runtime_name, server_command


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.model = self.root / '中文 模型.gguf'
        self.model.write_bytes(b'GGUF' + bytes(32))
        self.binary = self.root / 'llama-server'
        self.binary.touch()

    def arguments(self, *extra):
        return parser().parse_args(['--model', str(self.model), '--server', str(self.binary), *extra])

    def test_platform_and_architecture_matrix(self):
        for system, machine, expected in [
            ('Darwin', 'arm64', 'macos-arm64'), ('Darwin', 'x86_64', 'macos-x64'),
            ('Windows', 'AMD64', 'windows-x64'), ('Windows', 'ARM64', 'windows-arm64'),
        ]:
            self.assertEqual(runtime_name(system, machine), expected)
        for system, machine in [('Linux', 'x86_64'), ('Windows', 'x86')]:
            with self.assertRaises(ValueError):
                runtime_name(system, machine)

    def test_native_commands_use_metadata_template_and_loopback(self):
        for system, machine, layers in [('Darwin', 'arm64', '-1'), ('Windows', 'AMD64', '0')]:
            command = server_command(self.arguments(), system, machine)
            self.assertEqual(command[command.index('--model') + 1], str(self.model.resolve()))
            self.assertEqual(command[command.index('--alias') + 1], self.model.stem)
            self.assertEqual(command[command.index('--host') + 1], '127.0.0.1')
            self.assertEqual(command[command.index('--parallel') + 1], '1')
            self.assertEqual(command[command.index('--n-gpu-layers') + 1], layers)
            for flag in ('--jinja', '--no-context-shift', '--no-cache-prompt', '--offline', '--no-webui'):
                self.assertIn(flag, command)
            self.assertNotIn('--chat-template', command)
            self.assertEqual(command[command.index('--reasoning') + 1], 'off')

    def test_cpu_override_and_limits(self):
        command = server_command(self.arguments('--gpu-layers', '0', '--context-limit', '16384'), 'Darwin', 'arm64')
        self.assertEqual(command[command.index('--n-gpu-layers') + 1], '0')
        self.assertEqual(command[command.index('--ctx-size') + 1], '16384')
        for extra in [('--port', '0'), ('--threads', '0'), ('--context-limit', '0'), ('--gpu-layers', '-2')]:
            with self.assertRaises(ValueError):
                server_command(self.arguments(*extra), 'Windows', 'AMD64')

    def test_rejects_pth_corrupt_or_missing_weights_and_missing_runtime(self):
        weights = self.root / 'old.pth'
        weights.touch()
        with self.assertRaisesRegex(ValueError, 'gguf'):
            server_command(self.arguments('--model', str(weights)), 'Darwin', 'arm64')
        self.model.write_bytes(b'junk')
        with self.assertRaisesRegex(ValueError, 'header'):
            server_command(self.arguments(), 'Darwin', 'arm64')
        self.model.unlink()
        with self.assertRaises(ValueError):
            server_command(self.arguments(), 'Darwin', 'arm64')
        self.model.write_bytes(b'GGUF')
        self.binary.unlink()
        with self.assertRaisesRegex(ValueError, 'prepare-local-rwkv'):
            server_command(self.arguments(), 'Darwin', 'arm64')


if __name__ == '__main__':
    unittest.main()
