#!/usr/bin/env python3
"""Package the already built app for a GitHub release."""
from pathlib import Path
import hashlib
import zipfile

app = Path('build/Warp Voice.app')
if not (app / 'Contents/MacOS/WarpVoice').is_file():
    raise SystemExit('Build the application first with ./build.sh')
output = Path('build/Warp-Voice.zip')
with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as z:
    for path in sorted(app.rglob('*')):
        if path.is_file(): z.write(path, path.relative_to(app.parent))
print(f'{output} sha256={hashlib.sha256(output.read_bytes()).hexdigest()}')
