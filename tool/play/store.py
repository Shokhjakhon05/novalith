#!/usr/bin/env python3
"""Uploads the Novalith store listing to Play Console in one edit: texts for every language in
docs/store/LISTING.md, the icon, the feature graphic and the phone screenshots.

Needs the app to exist in Play Console already (the API cannot create an app) and the OAuth
token of ~/play-console-api. Run with that folder's Python:

    ~/play-console-api/.venv/bin/python tool/play/store.py            # dry run, changes nothing
    ~/play-console-api/.venv/bin/python tool/play/store.py --commit
"""
import os
import sys

PC = os.path.expanduser('~/play-console-api')
sys.path.insert(0, PC)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(PC)

import requests  # noqa: E402
from pc import h  # noqa: E402
from listing import load  # noqa: E402

PKG = 'com.novalith.game'
B = f'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PKG}'
U = f'https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PKG}'
STORE = os.path.join(ROOT, 'docs', 'store')
# Screenshots exist in English and Russian; every other language shows the default (English).
SHOT_DIRS = {'en-US': 'en', 'ru-RU': 'ru'}
COMMIT = '--commit' in sys.argv


def report(r, what):
    print(f'  {what}: {r.status_code}' + ('' if r.ok else ' ' + r.text[:300]))
    return r.ok


def upload(edit, lang, kind, path):
    with open(path, 'rb') as f:
        r = requests.post(f'{U}/edits/{edit}/listings/{lang}/{kind}?uploadType=media',
                          headers={**h(), 'Content-Type': 'image/png'}, data=f.read(), timeout=300)
    if not r.ok:
        print(f'  {lang} {kind} {os.path.basename(path)}: {r.status_code} {r.text[:200]}')
    return r.ok


def main():
    listings = load()
    r = requests.post(f'{B}/edits', headers=h(), timeout=60)
    if not r.ok:
        print('Cannot open an edit:', r.status_code, r.text[:300])
        print('Create the app in Play Console first (package com.novalith.game).')
        sys.exit(1)
    edit = r.json()['id']
    try:
        report(requests.patch(f'{B}/edits/{edit}/details', headers=h(), timeout=60, json={
            'defaultLanguage': 'en-US',
            'contactEmail': 'xarisiddin@gmail.com',
            'contactWebsite': 'https://shokhjakhon05.github.io/',
        }), 'details')
        for lang, texts in listings.items():
            if not report(requests.put(f'{B}/edits/{edit}/listings/{lang}', headers=h(), timeout=60,
                                       json={'language': lang, **texts}), f'listing {lang}'):
                continue
            if lang in SHOT_DIRS:
                shots = sorted(f for f in os.listdir(os.path.join(STORE, 'screens', SHOT_DIRS[lang])) if f.endswith('.png'))
                images = [('icon', [os.path.join(STORE, 'play_icon_512.png')]),
                          ('featureGraphic', [os.path.join(STORE, 'feature_graphic_1024x500.png')]),
                          ('phoneScreenshots', [os.path.join(STORE, 'screens', SHOT_DIRS[lang], f) for f in shots])]
                for kind, files in images:
                    requests.delete(f'{B}/edits/{edit}/listings/{lang}/{kind}', headers=h(), timeout=60)
                    done = sum(upload(edit, lang, kind, f) for f in files)
                    print(f'  {lang} {kind}: {done}/{len(files)} uploaded')
        if COMMIT:
            c = requests.post(f'{B}/edits/{edit}:commit', headers=h(), timeout=120)
            print('COMMIT', c.status_code, '' if c.ok else c.text[:500])
            if c.ok:
                return
        else:
            v = requests.post(f'{B}/edits/{edit}:validate', headers=h(), timeout=120)
            print('VALIDATE (dry run, nothing saved)', v.status_code, '' if v.ok else v.text[:500])
        requests.delete(f'{B}/edits/{edit}', headers=h(), timeout=60)
    except Exception:
        requests.delete(f'{B}/edits/{edit}', headers=h(), timeout=60)
        raise


if __name__ == '__main__':
    main()
