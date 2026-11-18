"""Download the pinned RWKV checkpoint; resume partial files and verify SHA-256."""

import argparse
import hashlib
import json
from pathlib import Path
import time
from urllib.request import Request, urlopen


REPO = 'BlinkDL/temp-latest-training-models'
REVISION = '70e6d2849493a08a5556944b73b57ba85788c5c0'
FILENAME = 'rwkv-g1m-1b-temp-6629-ctx65536.pth'
SIZE = 3055444605
SHA256 = '53193f7dfa65cad5edc3ec7c664a14f40f70f71338e46af4e9e9d21608affb6d'


def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=Path(__file__).resolve().parents[1] / 'local-models')
    parser.add_argument('--mirror', action='store_true', help='Explicitly use hf-mirror.com')
    args = parser.parse_args()
    args.directory.mkdir(parents=True, exist_ok=True)
    destination = args.directory / FILENAME
    if destination.exists():
        if destination.stat().st_size == SIZE and digest(destination) == SHA256:
            print(f'Already verified: {destination}')
            return
        raise SystemExit('Existing destination differs from the pinned model; move it before retrying.')
    partial = destination.with_suffix('.pth.part')
    offset = partial.stat().st_size if partial.exists() else 0
    if offset > SIZE:
        raise SystemExit('Partial download is larger than expected; remove the .part file before retrying.')
    host = 'https://hf-mirror.com' if args.mirror else 'https://huggingface.co'
    # The offset is included in the URL to avoid proxy caches reusing a previous
    # byte-range response with a different Range request.
    url = f'{host}/{REPO}/resolve/{REVISION}/{FILENAME}?download=true&offset={offset}'
    if offset < SIZE:
        request = Request(url, headers={'Range': f'bytes={offset}-'} if offset else {})
        print(f'Downloading {SIZE / 1e9:.2f} GB from {host}; resuming at {offset} bytes.', flush=True)
        with urlopen(request, timeout=60) as response:
            if offset and response.status == 200:
                offset = 0  # Origin does not support resuming; safely restart.
            elif offset and (response.status != 206 or not response.headers.get('Content-Range', '').startswith(f'bytes {offset}-')):
                raise SystemExit('Server returned an unexpected byte range.')
            with partial.open('ab' if offset else 'wb') as target:
                last = time.monotonic()
                while chunk := response.read(4 * 1024 * 1024):
                    target.write(chunk)
                    offset += len(chunk)
                    if offset > SIZE:
                        raise SystemExit('Download exceeded expected size.')
                    if time.monotonic() - last >= 5:
                        print(f'{offset / SIZE:.1%} ({offset / 1e9:.2f} GB)', flush=True)
                        last = time.monotonic()
    if partial.stat().st_size != SIZE or digest(partial) != SHA256:
        raise SystemExit('Model integrity check failed; remove the .part file and download again.')
    partial.replace(destination)
    destination.with_suffix('.provenance.json').write_text(json.dumps({
        'repository': REPO, 'revision': REVISION, 'filename': FILENAME, 'bytes': SIZE,
        'sha256': SHA256, 'downloadHost': host,
    }, indent=2), encoding='utf-8')
    print(f'Verified: {destination}')


if __name__ == '__main__':
    main()
