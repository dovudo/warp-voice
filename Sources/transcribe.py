#!/usr/bin/env python3
"""Experimental use of the installed Warp session for transcription on macOS.

Uses unsupported internal interfaces; keep credentials in memory only.
"""
import argparse
import base64
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import wave
from pathlib import Path

parser = argparse.ArgumentParser(description='Transcribe a WAV using the installed Warp session')
parser.add_argument('wav', type=Path)
parser.add_argument('--language', default=None, help='ISO language code; omit to auto-detect')
parser.add_argument('--team', help='Warp team UID if required')
args = parser.parse_args()
try:
    with wave.open(str(args.wav), 'rb') as wav:
        if wav.getnchannels() != 1 or wav.getsampwidth() != 2:
            sys.exit('Use a mono 16-bit PCM WAV file.')
    audio = args.wav.read_bytes()
    entry = subprocess.run(['security', 'find-generic-password', '-s', 'dev.warp.Warp-Stable', '-a', 'User', '-w'], capture_output=True, check=True, timeout=30)
    refresh = json.loads(entry.stdout)['id_token']['refresh_token']
    binary = subprocess.run(['strings', '/Applications/Warp.app/Contents/MacOS/stable'], capture_output=True, check=True).stdout
    identifiers = set(re.findall(rb'AIza[0-9A-Za-z_-]{35}', binary))
    if len(identifiers) != 1:
        sys.exit('Could not uniquely identify the installed Warp Firebase client.')
    client_id = next(iter(identifiers)).decode('ascii')
    body = urllib.parse.urlencode({'grant_type': 'refresh_token', 'refresh_token': refresh}).encode()
    request = urllib.request.Request('https://securetoken.googleapis.com/v1/token?key=' + client_id, data=body, method='POST')
    with urllib.request.urlopen(request, timeout=30) as response:
        token = json.load(response)['id_token']
    data = {'provider': 'wispr', 'audio': base64.b64encode(audio).decode()}
    if args.language:
        data['language'] = args.language
    payload = json.dumps(data).encode()
    headers = {'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'}
    if args.team:
        headers['X-Warp-Team-Uid'] = args.team
    request = urllib.request.Request('https://app.warp.dev/ai/transcribe', data=payload, headers=headers, method='POST')
    started = time.monotonic()
    with urllib.request.urlopen(request, timeout=60) as response:
        result = json.load(response)
        print(result['text'])
        print(f'HTTP {response.status}; {time.monotonic() - started:.2f}s', file=sys.stderr)
except urllib.error.HTTPError as exc:
    sys.exit(f'Server returned HTTP {exc.code}; transcription failed.')
except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
    sys.exit('Could not access Warp Keychain entry or read the installed app.')
except (OSError, ValueError, KeyError, wave.Error) as exc:
    sys.exit(f'Unable to process the session or WAV ({type(exc).__name__}).')
