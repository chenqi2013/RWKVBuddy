"""Build the pinned llama.cpp GGUF runtime for the current Windows or macOS host."""

import argparse
import json
import os
import platform
from pathlib import Path
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[1]
REVISION = 'e4b620af19f02960dea7a3a81de7c5805aa3a333'
REPOSITORY = 'https://github.com/ggml-org/llama.cpp.git'
def runtime_name():
    system = platform.system()
    architectures = {'arm64': 'arm64', 'aarch64': 'arm64', 'amd64': 'x64', 'x86_64': 'x64'}
    machine = platform.machine().lower()
    if system not in ('Windows', 'Darwin') or machine not in architectures:
        raise ValueError('Local GGUF inference supports Windows/macOS x64 and ARM64')
    return f'{"windows" if system == "Windows" else "macos"}-{architectures[machine]}'


def main():
    options = argparse.ArgumentParser(description=__doc__)
    options.add_argument('--source', type=Path, help='Existing checkout of the pinned llama.cpp revision')
    options.add_argument('--jobs', type=int, default=max(1, min(8, os.cpu_count() or 4)))
    args = options.parse_args()
    try:
        runtime = runtime_name()
    except ValueError as error:
        options.error(str(error))
    if args.jobs < 1:
        options.error('--jobs must be positive')
    for tool in ('git', 'cmake'):
        if not shutil.which(tool):
            options.error(f'{tool} is required; see docs/local-rwkv.md')
    source = (args.source or ROOT / 'build' / 'llama.cpp').resolve()
    if not source.exists():
        source.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(['git', 'init', str(source)], check=True)
        subprocess.run(['git', '-C', str(source), 'fetch', '--depth', '1', REPOSITORY, REVISION], check=True)
        subprocess.run(['git', '-C', str(source), 'checkout', '--detach', 'FETCH_HEAD'], check=True)
    actual = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != REVISION:
        options.error(f'llama.cpp revision mismatch: expected {REVISION}, found {actual}')
    build = ROOT / 'build' / f'llama-native-{runtime}'
    configure = ['cmake', '-S', str(ROOT / 'agent-service/local-model/native'), '-B', str(build),
                 f'-DLLAMA_SOURCE={source}', '-DCMAKE_BUILD_TYPE=Release',
                 '-DBUILD_SHARED_LIBS=OFF', '-DGGML_BACKEND_DL=OFF', '-DGGML_NATIVE=OFF',
                 '-DLLAMA_BUILD_TESTS=OFF', '-DLLAMA_BUILD_EXAMPLES=OFF', '-DLLAMA_BUILD_APP=OFF',
                 '-DLLAMA_BUILD_TOOLS=OFF', '-DLLAMA_BUILD_SERVER=OFF', '-DLLAMA_BUILD_UI=OFF',
                 '-DLLAMA_OPENSSL=OFF']
    if runtime.startswith('windows'):
        configure.extend(['-A', 'ARM64' if runtime.endswith('arm64') else 'x64', '-DGGML_CUDA=OFF'])
    else:
        configure.extend(['-DGGML_METAL=ON', '-DGGML_METAL_EMBED_LIBRARY=ON',
                          f'-DCMAKE_OSX_ARCHITECTURES={"arm64" if runtime.endswith("arm64") else "x86_64"}'])
    subprocess.run(configure, check=True)
    subprocess.run(['cmake', '--build', str(build), '--config', 'Release', '--target', 'rwkvbuddy-inference',
                    '--parallel', str(args.jobs)], check=True)
    filename = 'rwkvbuddy-inference.exe' if runtime.startswith('windows') else 'rwkvbuddy-inference'
    candidates = [build / 'bin' / 'Release' / filename, build / 'bin' / filename]
    binary = next((path for path in candidates if path.is_file()), None)
    if binary is None:
        raise RuntimeError('Build succeeded but rwkvbuddy-inference was not found')
    destination = ROOT / 'agent-service' / 'runtime' / 'llama' / runtime
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copy2(binary, destination / filename)
    shutil.copy2(source / 'LICENSE', destination / 'LICENSE-llama.cpp')
    (destination / 'runtime.json').write_text(json.dumps({
        'repository': REPOSITORY, 'revision': REVISION, 'platform': runtime,
        'backend': 'Metal / CPU' if runtime.startswith('macos') else 'CPU',
        'transport': 'stdio', 'http': False,
    }, indent=2), encoding='utf-8')
    if runtime.startswith('macos'):
        subprocess.run(['codesign', '--force', '--sign', '-', str(destination / filename)], check=True)
    subprocess.run([str(destination / filename), '--version'], check=True)
    print(f'Prepared: {destination}', flush=True)


if __name__ == '__main__':
    main()
