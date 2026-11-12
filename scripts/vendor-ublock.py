#!/usr/bin/env python3
"""Restore mica's pinned uBO inputs from the official AMO package, checking its SHA-256.
Upstream files are copied unchanged; the integration module and NOTICE are maintained separately.
"""
import hashlib
import io
import pathlib
import urllib.request
import zipfile

URL = 'https://addons.mozilla.org/firefox/downloads/file/5225273/ublock_origin-1.76.0.xpi'
SHA256 = '6f20ff6749193599548770539103069c20948dfcd3e61c3089a67da7bfc3be39'
root = pathlib.Path(__file__).resolve().parent.parent / 'shared/blocking/ublock'
with urllib.request.urlopen(URL, timeout=60) as response:
    data = response.read(20_000_001)
if len(data) > 20_000_000 or hashlib.sha256(data).hexdigest() != SHA256:
    raise SystemExit('uBO package size or SHA-256 mismatch; no files changed')
with zipfile.ZipFile(io.BytesIO(data)) as archive:
    for name in archive.namelist():
        if name.endswith('/') or not (name.startswith(('js/', 'lib/', 'assets/')) or name in ('LICENSE.txt', 'manifest.json')):
            continue
        if name.startswith('assets/thirdparties/urlhaus-filter/'):
            continue
        relative = pathlib.PurePosixPath(name)
        if relative.is_absolute() or '..' in relative.parts:
            raise SystemExit('invalid package path')
        target = root.joinpath(*relative.parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(archive.read(name))
print('Restored uBlock Origin 1.76.0, SHA-256 verified')
