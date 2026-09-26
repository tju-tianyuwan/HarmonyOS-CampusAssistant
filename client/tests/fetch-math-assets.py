"""Fetch pinned browser distributions without running package install scripts."""
from pathlib import Path
import hashlib, io, json, tarfile, urllib.request

ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'entry/src/main/resources/rawfile/math'
PACKAGES={'katex':'0.18.9','marked':'18.0.14','dompurify':'3.4.16'}
records=[]
for name,version in PACKAGES.items():
    info=json.load(urllib.request.urlopen(f'https://registry.npmjs.org/{name}/{version}',timeout=30))
    archive=urllib.request.urlopen(info['dist']['tarball'],timeout=60).read()
    assert hashlib.sha1(archive).hexdigest()==info['dist']['shasum'], 'Package integrity mismatch'
    with tarfile.open(fileobj=io.BytesIO(archive),mode='r:gz') as package:
        selected=[]
        for entry in package.getmembers():
            relative=entry.name.removeprefix('package/')
            wanted=(name=='katex' and (relative in ['dist/katex.min.js','dist/katex.min.css'] or relative.startswith('dist/fonts/'))
                or name=='marked' and relative=='lib/marked.umd.js'
                or name=='dompurify' and relative=='dist/purify.min.js'
                or relative in ['LICENSE','LICENSE.md','LICENSE.txt'])
            if not wanted or not entry.isfile():continue
            relative=relative.removeprefix('dist/').removeprefix('lib/')
            target=(DEST/name/relative).resolve()
            assert target.is_relative_to(DEST.resolve())
            target.parent.mkdir(parents=True,exist_ok=True)
            data=package.extractfile(entry).read()
            target.write_bytes(data)
            selected.append({'file':str(target.relative_to(DEST)),'sha256':hashlib.sha256(data).hexdigest()})
        records.append({'package':name,'version':version,'source':info['dist']['tarball'],'files':selected})
(DEST/'vendor-manifest.json').write_text(json.dumps(records,indent=2),encoding='utf-8')
print('Fetched pinned, licensed, offline math assets:',[(r['package'],len(r['files'])) for r in records])
