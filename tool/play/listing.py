"""Parses docs/store/LISTING.md into Play Console listings: {locale: {title, shortDescription,
fullDescription}}. One source of truth for the store texts; limits are checked here."""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def load():
    text = open(os.path.join(ROOT, 'docs', 'store', 'LISTING.md'), encoding='utf-8').read()
    out = {}
    for block in re.split(r'\n## ', text)[1:]:
        head, _, body = block.partition('\n')
        m = re.search(r'\(([A-Za-z0-9\- /]+)\)', head)
        if not m:
            continue
        title = re.search(r'\*\*Title:\*\*\s*(.+)', body).group(1).strip()
        short = re.search(r'\*\*Short description:\*\*\s*(.+)', body).group(1).strip()
        full = body.split('**Full description:**', 1)[1].split('\n---', 1)[0].strip()
        # Paragraphs were wrapped for the Markdown file; join the wrapped lines back.
        paras = []
        for para in full.split('\n\n'):
            lines = para.split('\n')
            if all(l.startswith('•') for l in lines):
                paras.append('\n'.join(lines))
            else:
                joined = ''
                for l in lines:
                    if l.startswith('•') or not joined:
                        joined += ('\n' if joined else '') + l
                    else:
                        cjk = re.search(r'[぀-ヿ一-鿿]$', joined) is not None
                        joined += ('' if cjk else ' ') + l
                paras.append(joined)
        full = '\n\n'.join(paras)
        for locale in [c.strip() for c in m.group(1).split('/')]:
            out[locale] = {'title': title, 'shortDescription': short, 'fullDescription': full}
    for locale, l in out.items():
        assert len(l['title']) <= 30, (locale, 'title', len(l['title']))
        assert len(l['shortDescription']) <= 80, (locale, 'short', len(l['shortDescription']))
        assert len(l['fullDescription']) <= 4000, (locale, 'full', len(l['fullDescription']))
    return out


if __name__ == '__main__':
    data = load()
    for locale, l in data.items():
        print(f"{locale:8} title {len(l['title']):2}/30  short {len(l['shortDescription']):2}/80  full {len(l['fullDescription'])}/4000  {l['title']}")
    print(len(data), 'locales')
    print('---\n' + data['ru-RU']['fullDescription'])
