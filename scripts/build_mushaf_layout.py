"""Bundle Quran.com v4 Madinah word/marker locations without changing text.

Run with Python 3.11+. Standard library only. Cached responses are resumable.
The corpus is checked word-for-word before a new layout asset is written.
"""
import concurrent.futures
import gzip
import json
import re
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / 'mobile/assets/quran_corpus.json.gz'
OUTPUT = ROOT / 'mobile/assets/mushaf_layout.json.gz'
CACHE = ROOT / 'mobile/.dart_tool/mushaf-layout-api'
ARABIC = re.compile(r'[\u0621-\u063a\u0641-\u064a\u0671]')


def fetch(surah):
    verses = []
    page = 1
    while True:
        path = CACHE / f'{surah}-{page}.json'
        if path.exists():
            data = json.loads(path.read_text(encoding='utf-8'))
        else:
            url = (f'https://api.quran.com/api/v4/verses/by_chapter/{surah}'
                   f'?words=true&word_fields=page_number,line_number,text_uthmani'
                   f'&per_page=50&page={page}')
            for attempt in range(5):
                try:
                    request = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 QariLayoutBuilder'})
                    with urllib.request.urlopen(request, timeout=60) as response:
                        data = json.load(response)
                    path.write_text(json.dumps(data, ensure_ascii=False), encoding='utf-8')
                    break
                except Exception:
                    if attempt == 4:
                        raise
                    time.sleep(2 ** attempt)
        verses.extend(data['verses'])
        if not data['pagination']['next_page']:
            return verses
        page = data['pagination']['next_page']


def build():
    CACHE.mkdir(parents=True, exist_ok=True)
    corpus = json.loads(gzip.decompress(CORPUS.read_bytes()))
    by_ref = {f"{s['surah_number']}:{a['ayah_number']}": a
              for s in corpus['surahs'] for a in s['ayahs']}
    result = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for verses in pool.map(fetch, range(1, 115)):
            for verse in verses:
                ref = verse['verse_key']
                local = [w for w in by_ref[ref]['words'] if ARABIC.search(w['text'])]
                remote = [w for w in verse['words'] if w['char_type_name'] == 'word']
                if len(local) != len(remote):
                    raise ValueError(f'{ref}: corpus/API word count mismatch')
                # Diacritics and annotation encodings can differ, letter order cannot.
                for a, b in zip(local, remote):
                    if ARABIC.findall(a['text']) != ARABIC.findall(b['text_uthmani']):
                        raise ValueError(f'{ref}:{a["word_number"]}: letter mismatch')
                locations = [[w['page_number'], w['line_number']] for w in remote]
                marker = next(w for w in verse['words'] if w['char_type_name'] == 'end')
                locations.append([marker['page_number'], marker['line_number']])
                if any(not (1 <= p <= 604 and 1 <= line <= 15) for p, line in locations):
                    raise ValueError(f'{ref}: invalid page/line')
                result[ref] = locations
            print(f'Validated {len(result)}/6236 ayahs', flush=True)
    if set(result) != set(by_ref) or len(result) != 6236:
        raise ValueError('Incomplete Quran layout')
    asset = {'source': 'https://api.quran.com/api/v4', 'mushaf': 'Madinah 604 pages',
             'verses': dict(sorted(result.items(), key=lambda item: tuple(map(int, item[0].split(':')))))}
    OUTPUT.write_bytes(gzip.compress(json.dumps(asset, separators=(',', ':')).encode(), mtime=0))
    print(f'Wrote {OUTPUT} ({OUTPUT.stat().st_size} bytes)', flush=True)


if __name__ == '__main__':
    build()
