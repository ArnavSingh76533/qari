"""Bundle canonical printed line ends from the public Quran.com v4 API.

Run: python3 scripts/build_mushaf_layout.py (requires curl).
Matches every verse's body-word count to the shipped corpus without changing
text or ASR indices. Pages whose corpus verse spans another printed page keep
natural wrapping. Only page/line positions are stored; no glyphs are fetched.
"""
import concurrent.futures,json,subprocess,time,pathlib,collections,gzip
base='https://api.quran.com/api/v4'
root=pathlib.Path(__file__).resolve().parent.parent
cache=root/'.mushaf-layout-source';cache.mkdir(exist_ok=True)
def fetch(ch):
 p=cache/f'{ch}.json'
 if p.exists():return json.loads(p.read_text())
 verses=[];page=1
 while page:
  url=f'{base}/verses/by_chapter/{ch}?words=true&word_fields=line_number,page_number&per_page=300&page={page}'
  for attempt in range(3):
   try:
    j=json.loads(subprocess.check_output(['curl','--fail','--location','--silent','--show-error','--max-time','30',url]))
    break
   except Exception:
    if attempt==2:raise
  verses+=j['verses'];page=j['pagination']['next_page']
 p.write_text(json.dumps(verses));return verses
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
 allv=[]
 for ch,v in zip(range(1,115),pool.map(fetch,range(1,115))):
  allv+=v
  if ch%10==0:print('Fetched chapter',ch,flush=True)
lookup={v['verse_key']:[(w['page_number'],w['line_number']) for w in v['words'] if w['char_type_name']=='word'] for v in allv}
corpus=json.loads(gzip.decompress((root/'mobile/assets/quran_corpus.json.gz').read_bytes()))
pages=collections.defaultdict(list)
for s in corpus['surahs']:
 for a in s['ayahs']:
  key=f"{a['surah_number']}:{a['ayah_number']}";meta=lookup[key]
  body=[w for w in a['words'] if any('\u0621'<=c<='\u064a' for c in w['text'])]
  assert len(meta)==len(body),(key,len(meta),len(body))
  pages[a['page_number']]+=meta
bad=[];ends={}
for page,meta in sorted(pages.items()):
 if any(p!=page for p,l in meta):bad.append(page);continue
 end=[i for i in range(len(meta)) if i==len(meta)-1 or meta[i+1]!=meta[i]]
 ends[str(page)]=end
print('Validated canonical pages',len(ends),'multi-page-ayah pages',bad,flush=True)
print('Page 3 body line ends:',ends['3'],flush=True)
(root/'mobile/assets/mushaf_line_ends.json').write_text(json.dumps({'source':base,'pages':ends},separators=(',',':'))+'\n')
