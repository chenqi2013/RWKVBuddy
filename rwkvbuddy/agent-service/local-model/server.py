"""Launch the native llama.cpp RWKV-7 GGUF server on Windows or macOS."""

import argparse
import os
from pathlib import Path
import platform
import subprocess


MODEL_ID = 'rwkv7-g1l-1.5b-Q4_K_M'


def runtime_name(system=None, machine=None):
    system = system or platform.system()
    machine = (machine or platform.machine()).lower()
    if system not in ('Windows', 'Darwin'):
        raise ValueError('Local GGUF inference supports Windows and macOS only')
    architectures = {'arm64': 'arm64', 'aarch64': 'arm64', 'amd64': 'x64', 'x86_64': 'x64'}
    if machine not in architectures:
        raise ValueError(f'Unsupported architecture: {machine}')
    return f'{"windows" if system == "Windows" else "macos"}-{architectures[machine]}'


def parser():
    options = argparse.ArgumentParser(description=__doc__)
    options.add_argument('--model', type=Path, required=True)
    options.add_argument('--server', type=Path, help='Override the prepared llama-server executable')
    options.add_argument('--port', type=int, default=8099)
    options.add_argument('--threads', type=int, default=max(1, min(8, os.cpu_count() or 4)))
    options.add_argument('--context-limit', type=int, default=8192)
    options.add_argument('--gpu-layers', type=int, default=None,
                         help='Default: all layers on macOS Metal; CPU on Windows. Use 0 for CPU.')
    return options


def server_command(args, system=None, machine=None):
    system = system or platform.system()
    runtime = runtime_name(system, machine)
    model = args.model.expanduser().resolve()
    if not model.is_file() or model.suffix.lower() != '.gguf':
        raise ValueError('--model must point to an existing .gguf file')
    with model.open('rb') as source:
        if source.read(4) != b'GGUF':
            raise ValueError('Invalid GGUF file header')
    if not 1 <= args.port <= 65535 or args.threads < 1:
        raise ValueError('Invalid port or thread count')
    if not 512 <= args.context_limit <= 65536:
        raise ValueError('--context-limit must be between 512 and 65536')
    executable = args.server or (Path(__file__).resolve().parents[1] / 'runtime' / 'llama' /
                                 runtime / ('llama-server.exe' if system == 'Windows' else 'llama-server'))
    executable = executable.expanduser().resolve()
    if not executable.is_file():
        raise ValueError('llama-server is missing. Run: python scripts/prepare-local-rwkv.py')
    layers = args.gpu_layers if args.gpu_layers is not None else (-1 if system == 'Darwin' else 0)
    if layers < -1:
        raise ValueError('--gpu-layers must be -1 or greater')
    return [str(executable), '--model', str(model), '--alias', model.stem,
            '--host', '127.0.0.1', '--port', str(args.port), '--ctx-size', str(args.context_limit),
            '--parallel', '1', '--threads', str(args.threads), '--n-gpu-layers', str(layers),
            '--jinja', '--reasoning', 'off', '--reasoning-format', 'deepseek',
            '--no-context-shift', '--no-cache-prompt', '--offline', '--no-webui']


def main():
    options = parser()
    args = options.parse_args()
    try:
        command = server_command(args)
    except ValueError as error:
        options.error(str(error))
    environment = {key: value for key, value in os.environ.items() if not key.startswith('LLAMA_ARG_')}
    print(f'Loading GGUF: {args.model.name}; service: http://127.0.0.1:{args.port}/v1', flush=True)
    process = subprocess.Popen(command, env=environment)
    try:
        return process.wait()
    except KeyboardInterrupt:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        return 130


if __name__ == '__main__':
    raise SystemExit(main())
