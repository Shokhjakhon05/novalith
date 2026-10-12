#!/usr/bin/env python3
"""Uploads an App Bundle to a Play Console testing track.

    ~/play-console-api/.venv/bin/python tool/play/release.py <app-release.aab> [track] [--commit]

track: internal (default), alpha (closed testing), beta, production.
Without --commit the bundle is uploaded into a temporary edit, validated and discarded.
"""
import os
import re
import sys

PC = os.path.expanduser('~/play-console-api')
sys.path.insert(0, PC)
args = [a for a in sys.argv[1:] if not a.startswith('--')]
COMMIT = '--commit' in sys.argv
AAB = os.path.abspath(os.path.expanduser(args[0]))
TRACK = args[1] if len(args) > 1 else 'internal'
with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'pubspec.yaml')) as f:
    VERSION = re.search(r'^version:\s*([\d.]+)', f.read(), re.M).group(1)
os.chdir(PC)

import requests  # noqa: E402
from pc import h  # noqa: E402

PKG = 'com.novalith.game'
B = f'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PKG}'
U = f'https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PKG}'
NOTES = [
    {'language': 'en-US', 'text': 'A "how to play" card before the first game, fewer ads for new players, no long wait after the last drop, the daily challenge ends as soon as its goal is reached, and the map now climbs from the bottom up.'},
    {'language': 'ru-RU', 'text': 'Подсказка «Как играть» перед первой игрой, меньше рекламы для новичков, нет долгого ожидания после последнего броска, испытание дня завершается сразу при достижении цели, карта теперь идёт снизу вверх.'},
]

r = requests.post(f'{B}/edits', headers=h(), timeout=60)
if not r.ok:
    print('Cannot open an edit:', r.status_code, r.text[:300])
    sys.exit(1)
edit = r.json()['id']
with open(AAB, 'rb') as f:
    up = requests.post(f'{U}/edits/{edit}/bundles?uploadType=media',
                       headers={**h(), 'Content-Type': 'application/octet-stream'}, data=f, timeout=1800)
print('upload', up.status_code, up.text[:300])
if not up.ok:
    requests.delete(f'{B}/edits/{edit}', headers=h(), timeout=60)
    sys.exit(1)
vc = up.json()['versionCode']
# A brand-new app is still a draft in Play Console and only accepts draft releases.
for status in ('completed', 'draft'):
    body = {'track': TRACK, 'releases': [{'name': f'{VERSION} ({vc})', 'versionCodes': [str(vc)], 'status': status, 'releaseNotes': NOTES}]}
    t = requests.put(f'{B}/edits/{edit}/tracks/{TRACK}', headers=h(), json=body, timeout=60)
    print('track', TRACK, status, t.status_code, '' if t.ok else t.text[:300])
    if not t.ok:
        continue
    if not COMMIT:
        v = requests.post(f'{B}/edits/{edit}:validate', headers=h(), timeout=300)
        print('VALIDATE (dry run, nothing saved)', status, v.status_code, '' if v.ok else v.text[:500])
        if v.ok:
            break
        continue
    c = requests.post(f'{B}/edits/{edit}:commit', headers=h(), timeout=300)
    print('COMMIT', status, c.status_code, '' if c.ok else c.text[:500])
    if c.ok:
        sys.exit(0)
requests.delete(f'{B}/edits/{edit}', headers=h(), timeout=60)
