#!/usr/bin/env python3
"""GitHub Release checking and rollback-aware local installation."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import urllib.request
import zipfile

API = 'https://api.github.com/repos/dovudo/warp-voice/releases/latest'
ASSET = 'Warp-Voice.zip'
MAX_SIZE = 60 * 1024 * 1024

def version(value):
    match = re.fullmatch(r'v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', value)
    if not match: raise ValueError('Invalid release version')
    return tuple(map(int, match.groups()))

def is_newer(candidate, current):
    return version(candidate) > version(current)

def release_info(release, current):
    tag = release['tag_name']
    if not is_newer(tag, current): return {'available': False}
    matching = [a for a in release['assets'] if a.get('name') == ASSET]
    if len(matching) != 1: raise ValueError('Release archive missing')
    asset = matching[0]
    expected = 'https://github.com/dovudo/warp-voice/releases/download/' + tag + '/' + ASSET
    digest = asset.get('digest') or ''
    if asset.get('browser_download_url') != expected or not re.fullmatch(r'sha256:[a-f0-9]{64}', digest):
        raise ValueError('Release asset URL or SHA-256 is invalid')
    size = asset.get('size')
    if not isinstance(size, int) or not 0 < size <= MAX_SIZE: raise ValueError('Release size is invalid')
    return {'available': True, 'version': tag.lstrip('v'), 'url': expected, 'digest': digest[7:], 'size': size}

def latest(current):
    request = urllib.request.Request(API, headers={'Accept':'application/vnd.github+json', 'User-Agent':'WarpVoice-Updater'})
    with urllib.request.urlopen(request, timeout=15) as response:
        return release_info(json.load(response), current)

def unpack(archive, dest):
    with zipfile.ZipFile(archive) as z:
        items = z.infolist()
        if not items or sum(i.file_size for i in items) > MAX_SIZE * 3: raise ValueError('Invalid archive size')
        for item in items:
            p = PurePosixPath(item.filename)
            mode = item.external_attr >> 16
            if p.is_absolute() or '..' in p.parts or not p.parts or p.parts[0] != 'Warp Voice.app' or stat.S_ISLNK(mode):
                raise ValueError('Unsafe archive contents')
        z.extractall(dest)
    app = dest / 'Warp Voice.app'
    exe = app / 'Contents/MacOS/WarpVoice'
    if not exe.is_file(): raise ValueError('Application executable missing')
    exe.chmod(0o755)
    return app

def swap_app(target, staged, backup):
    os.rename(target, backup)
    try: os.rename(staged, target)
    except BaseException:
        os.rename(backup, target)
        raise

def validate(app, expected_version):
    subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(app)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
    import plistlib
    with (app/'Contents/Info.plist').open('rb') as f: info=plistlib.load(f)
    if info.get('CFBundleIdentifier') != 'local.dov.warpvoice' or info.get('CFBundleShortVersionString') != expected_version:
        raise ValueError('Application identity or version mismatch')

def apply_update(target, stage, backup, pid):
    for _ in range(150):
        try: os.kill(pid, 0)
        except ProcessLookupError: break
        time.sleep(.2)
    else: raise RuntimeError('App did not exit; update cancelled')
    swap_app(target, stage, backup)
    try:
        subprocess.run(['/usr/bin/open',str(target)], check=True, timeout=15)
    except Exception:
        shutil.rmtree(target, ignore_errors=True)
        os.rename(backup,target)
        subprocess.run(['/usr/bin/open',str(target)], check=False)
        raise
    # Keep the previous app in the private staging directory for manual recovery.

def install(target, current, expected):
    target=Path(target).resolve()
    if target.name != 'Warp Voice.app' or not target.is_dir(): raise ValueError('Invalid installation location')
    info=latest(current)
    if not info.get('available') or info['version'] != expected: raise ValueError('Release changed; check for updates again')
    work=Path(tempfile.mkdtemp(prefix='.warpvoice-update-',dir=target.parent))
    try:
        req=urllib.request.Request(info['url'],headers={'User-Agent':'WarpVoice-Updater'})
        with urllib.request.urlopen(req,timeout=60) as response:
            data=response.read(MAX_SIZE+1)
        if len(data) != info['size'] or hashlib.sha256(data).hexdigest() != info['digest']:
            raise ValueError('Downloaded archive failed SHA-256 verification')
        archive=work/ASSET; archive.write_bytes(data)
        stage=unpack(archive,work)
        validate(stage,info['version'])
        backup=work/'previous.app'
        # The copied helper survives the old app exiting and being replaced.
        helper=work/'updater.py'; shutil.copyfile(__file__,helper)
        subprocess.Popen(['/usr/bin/python3',str(helper),'apply',str(target),str(stage),str(backup),str(os.getppid()),str(work)], start_new_session=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except BaseException:
        shutil.rmtree(work,ignore_errors=True)
        raise

def main():
    p=argparse.ArgumentParser(); sub=p.add_subparsers(dest='command',required=True)
    c=sub.add_parser('check'); c.add_argument('current')
    i=sub.add_parser('install'); i.add_argument('target'); i.add_argument('current'); i.add_argument('expected')
    a=sub.add_parser('apply'); a.add_argument('target'); a.add_argument('stage'); a.add_argument('backup'); a.add_argument('pid',type=int); a.add_argument('work')
    args=p.parse_args()
    if args.command == 'check': print(json.dumps(latest(args.current)))
    elif args.command == 'install': install(args.target,args.current,args.expected); print('{"ready":true}')
    else:
        try: apply_update(Path(args.target),Path(args.stage),Path(args.backup),args.pid)
        except Exception as exc:
            # Keep the staged directory on failure for recovery; never include secrets.
            log=Path.home()/'Library/Application Support/WarpVoice/diagnostic.log'
            try:
                with log.open('a') as f: f.write('Updater failed: '+type(exc).__name__+'\n')
            except OSError: pass
            if Path(args.target).exists():
                subprocess.run(['/usr/bin/open',args.target], check=False)
            return 1
        try: (Path(args.work)/ASSET).unlink()
        except OSError: pass
    return 0

if __name__ == '__main__':
    try: sys.exit(main())
    except Exception as exc:
        print('Update failed: '+type(exc).__name__+': '+str(exc),file=sys.stderr)
        sys.exit(1)
