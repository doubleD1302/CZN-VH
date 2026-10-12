"""Build a signed JP-slot bundle, never redistribute whole source chunks/manifests."""
import argparse,base64,hashlib,json,struct,subprocess,zipfile
from pathlib import Path
from czn_format import Archive,Database,validate_translation
from story_format import StoryTable

PROJECT=Path(__file__).resolve().parents[1]
APP=PROJECT/'czn_android_patcher'
OUT=PROJECT/'data/releases/android-v1.4.0'
STORY='db/story_main_part1new_260729@story.db'

def sha(data):return hashlib.sha256(data).hexdigest()
def sign(path):
    subprocess.run(['pwsh','-NoProfile','-File',str(PROJECT/'tools/sign_android_metadata.ps1'),'-InputFile',str(path),'-KeyFile',str(APP/'.signing/update-private.pk8'),'-OutputFile',str(path.with_suffix('.signed.json'))],check=True)
    return path.with_suffix('.signed.json').read_bytes()
def main():
    global OUT
    parser=argparse.ArgumentParser()
    parser.add_argument('--version',default='1.4.0')
    parser.add_argument('--code',type=int,default=10400)
    parser.add_argument('--output',type=Path)
    parser.add_argument('--embed',action='store_true')
    args=parser.parse_args()
    import re
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+',args.version) or args.code<10400:raise ValueError('Invalid version/code')
    OUT=args.output or PROJECT/'data/releases'/('android-v'+args.version)
    OUT.mkdir(parents=True,exist_ok=True)
    state=json.loads((PROJECT/'data/state.json').read_text('utf-8'))
    base=PROJECT/'data'/state['backup'].replace('\\','/')
    source=Archive(base);target=Archive(PROJECT.parent/'bin/appdata/cznlive/gameres')
    original_db=Database(source.read_file('text/ja/text.db'),require_native_phase=True)
    translated_db=Database(target.read_file('text/ja/text.db'),require_native_phase=True)
    if set(original_db.texts)!=set(translated_db.texts):raise ValueError('Text DB IDs changed')
    changed={k:v for k,v in translated_db.texts.items() if original_db.texts[k]!=v}
    errors=[k for k,v in changed.items() if validate_translation(original_db.texts[k],v)]
    if errors:raise ValueError(f'Token guard failed for {len(errors)} IDs')
    original_story=StoryTable(source.read_file(STORY));translated_story=StoryTable(target.read_file(STORY))
    if original_story.order!=translated_story.order or original_story.columns!=translated_story.columns:raise ValueError('Story metadata changed')
    story_changes=0;info=original_story.columns.index('info')
    for scene in original_story.order:
        av=original_story.values[scene];bv=translated_story.values[scene]
        if av[:info]+av[info+1:]!=bv[:info]+bv[info+1:]:raise ValueError('Non-info story field changed')
        old=original_story.scene(scene);new=translated_story.scene(scene)
        if len(old)!=len(new):raise ValueError('Story command count changed')
        for x,y in zip(old,new):
            if {k:v for k,v in x.items() if k!='text_ja'}!={k:v for k,v in y.items() if k!='text_ja'}:raise ValueError('Non-JP scene field changed')
            if x.get('text_ja')!=y.get('text_ja'):story_changes+=1
    patches=[];payloads={}
    for name,payload_name,chunk_name in [('text/ja/text.db','payload/text.zst','lang_ja_b01_0.ssrc'),(STORY,'payload/story.zst','base_b21_0.ssrc')]:
        f=source.files[name];g=target.files[name];segments=source.segments(f);next_segments=target.segments(g)
        if len(segments)!=1 or len(next_segments)!=1:raise ValueError('Unsupported split slot')
        c,off,size=segments[0];d,at,ns=next_segments[0]
        if c['name']!=chunk_name or d['name']!=chunk_name or at!=off or g['cs']>f['cs']:raise ValueError('Slot/chunk moved')
        sb=source.chunk_bytes(c);tb=target.chunk_bytes(d)
        if sb[:off]!=tb[:off] or sb[off+size:-8]!=tb[off+size:-8]:raise ValueError('Bytes outside JP slot changed')
        payload=tb[at:at+g['cs']];payloads[payload_name]=payload
        patches.append(dict(file=name,payload=payload_name,source_cs=f['cs'],source_us=f['us'],source_sha256=sha(sb[off:off+size]),source_xxh64=f"{struct.unpack_from('<Q',source.data,source.fhash+f['index']*8)[0]:016x}",target_cs=g['cs'],target_us=g['us'],target_sha256=sha(payload),target_xxh64=f"{struct.unpack_from('<Q',target.data,target.fhash+g['index']*8)[0]:016x}"))
    desc=dict(schema=2,version=args.version,version_code=args.code,min_patcher=10400,title='CZN Việt Hóa',changelog=f'{len(changed):,} mục văn bản đã đổi và {story_changes:,} câu cốt truyện. Giữ tên thẻ/kỹ năng EN theo ID.',patches=patches)
    raw=OUT/'release.descriptor.json';raw.write_text(json.dumps(desc,ensure_ascii=False,separators=(',',':')),encoding='utf-8');envelope=sign(raw)
    bundle=OUT/f'CZN_Android_v{args.version}.cznpatch'
    if bundle.exists():raise FileExistsError('Preserve old releases; choose a new version/output directory')
    with zipfile.ZipFile(bundle,'w',compression=zipfile.ZIP_STORED) as z:
        z.writestr('release.json',envelope)
        for name,data in payloads.items():z.writestr(name,data)
    if args.embed:
        (APP/'android/app/src/main/assets/bundled.cznpatch').write_bytes(bundle.read_bytes())
        (APP/'android/app/src/main/assets/bundled-release.json').write_bytes(envelope)
    key=base64.b64encode((APP/'android/app/src/main/assets/update-public.der').read_bytes()).decode()
    trust=APP/'android/app/src/main/java/vn/czn/viethoa/czn_patcher/BuildTrust.java'
    trust.write_text('package vn.czn.viethoa.czn_patcher;\npublic final class BuildTrust { public static final String PUBLIC_KEY = "'+key+'"; }\n',encoding='utf-8')
    evidence=dict(text_changes=len(changed),text_token_errors=0,story_changes=story_changes,native_readback=True,story_non_jp_fields_identical=True,outside_jp_slots_identical=True,bundle_bytes=bundle.stat().st_size,bundle_sha256=sha(bundle.read_bytes()),source_manifest_sha256=sha(source.data),target_manifest_sha256=sha(target.data),android_runtime='pending_device_verification')
    (OUT/'PACKAGE_EVIDENCE.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(evidence))
if __name__=='__main__':main()
