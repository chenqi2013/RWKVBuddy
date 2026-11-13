#!/usr/bin/env python3
"""Prepare standalone, universal Node.js and Lua binaries for the macOS app."""
import hashlib
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
RUNTIME = ROOT / 'agent-service' / 'runtime'


def download(url, target):
    subprocess.run(['/usr/bin/curl', '--fail', '--location', '--silent', '--show-error',
                    '--retry', '2', '--connect-timeout', '20', '--max-time', '60',
                    '--output', str(target), url], check=True)


def run(*args, **kwargs):
    subprocess.run(args, check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lua-only', action='store_true', help='Rebuild Lua without downloading Node.js again')
    options = parser.parse_args()
    RUNTIME.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='rwkvbuddy-macos-runtime-') as temporary:
        work = Path(temporary)
        if not options.lua_only:
            manifest = work / 'SHASUMS256.txt'
            download('https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt', manifest)
            checksums = dict(line.split()[::-1] for line in manifest.read_text().splitlines())
            nodes = []
            for arch in ('arm64', 'x64'):
                filename = next(name for name in checksums if name.endswith(f'-darwin-{arch}.tar.gz'))
                version = filename.split('-darwin-')[0].removeprefix('node-')
                archive = work / filename
                print(f'Downloading Node.js {version} ({arch})', flush=True)
                download(f'https://nodejs.org/dist/{version}/{filename}', archive)
                if hashlib.sha256(archive.read_bytes()).hexdigest() != checksums[filename]:
                    raise RuntimeError('Node.js archive checksum mismatch')
                run('tar', '-xzf', str(archive), '-C', str(work))
                nodes.append(str(work / filename.removesuffix('.tar.gz') / 'bin' / 'node'))
            run('xcrun', 'lipo', '-create', *nodes, '-output', str(RUNTIME / 'node'))

        # Build Lua independently for each architecture before joining the executables.
        archive = work / 'lua-5.4.8.tar.gz'
        download('https://www.lua.org/ftp/lua-5.4.8.tar.gz', archive)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != '4f18ddae154e793e46eeab727c59ef1c0c0c2b744e7b94219710d76f530629ae':
            raise RuntimeError('Lua archive checksum mismatch')
        luas = []
        for arch in ('arm64', 'x86_64'):
            source = work / arch
            source.mkdir()
            run('tar', '-xzf', str(archive), '-C', str(source))
            run('make', '-C', str(source / 'lua-5.4.8' / 'src'), 'generic',
                'CC=xcrun clang', f'MYCFLAGS=-arch {arch} -mmacosx-version-min=14.6 -DLUA_USE_POSIX -DLUA_USE_DLOPEN',
                f'MYLDFLAGS=-arch {arch} -mmacosx-version-min=14.6',
                stdout=subprocess.DEVNULL)
            luas.append(str(source / 'lua-5.4.8' / 'src' / 'lua'))
        run('xcrun', 'lipo', '-create', *luas, '-output', str(RUNTIME / 'lua'))
    for name in ('node', 'lua'):
        path = RUNTIME / name
        path.chmod(0o755)
        run('codesign', '--force', '--sign', '-', str(path))
        run(str(path), '--version' if name == 'node' else '-v')
    print('Prepared universal runtimes in agent-service/runtime', flush=True)


if __name__ == '__main__':
    main()
