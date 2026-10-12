"""Build and validate signed JP-slot bundles without redistributing source game chunks."""
import argparse,hashlib,json,struct,zipfile
from pathlib import Path
from czn_format import Archive,Database,validate_translation
from story_format import StoryTable
STORY='db/story_main_part1new_260729@story.db'
def sha(data):return hashlib.sha256(data).hexdigest()
def make_bundle(source,target,out,version,code,signer):
    out=Path(out);out.mkdir(parents=True,exist_ok=True)
    if (out/f'CZN_Android_v{version}.cznpatch').exists():raise FileExistsError('Giữ bản cũ; chọn phiên bản mới.')
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
    desc=dict(schema=2,version=version,version_code=code,min_patcher=10400,title='CZN Việt Hóa',changelog=f'{len(changed):,} mục văn bản đã đổi và {story_changes:,} câu cốt truyện. Giữ tên thẻ/kỹ năng EN theo ID.',patches=patches,notice=dict(enabled=True,id='welcome-1.4.1',title='Thông báo CZN Việt Hóa',body='Chọn ngôn ngữ văn bản 日本語 trong CZN và chờ tải đủ dữ liệu. Quay lại app, cấp quyền Shizuku rồi bấm Kiểm tra lại dữ liệu game.\n\nXiaomi: nếu Shizuku báo thiếu quyền, bật Gỡ lỗi USB (Cài đặt bảo mật) và khởi động lại Shizuku. Game và patcher cần ở cùng hồ sơ Android.\n\nBấm Kiểm tra cập nhật để nhận bản dịch và APK mới. Bạn có thể tắt thông báo này hoặc ẩn trong 24 giờ.'))
    raw=out/'release.descriptor.json';raw.write_text(json.dumps(desc,ensure_ascii=False,separators=(',',':')),encoding='utf-8');envelope=signer(raw)
    bundle=out/f'CZN_Android_v{version}.cznpatch'
    if bundle.exists():raise FileExistsError('Preserve old releases; choose a new version/output directory')
    with zipfile.ZipFile(bundle,'w',compression=zipfile.ZIP_STORED) as z:
        z.writestr('release.json',envelope)
        for name,data in payloads.items():z.writestr(name,data)
    evidence=dict(text_changes=len(changed),text_token_errors=0,story_changes=story_changes,native_readback=True,story_non_jp_fields_identical=True,outside_jp_slots_identical=True,bundle_bytes=bundle.stat().st_size,bundle_sha256=sha(bundle.read_bytes()),source_manifest_sha256=sha(source.data),target_manifest_sha256=sha(target.data),android_runtime='pending_device_verification')
    (out/'PACKAGE_EVIDENCE.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2),encoding='utf-8')
    return bundle,evidence
def main():
    from android_sync import sign_metadata
    from installer_core import Installer
    project=Path(__file__).resolve().parents[1]
    parser=argparse.ArgumentParser();parser.add_argument('--version',default='1.4.1');parser.add_argument('--code',type=int,default=10401);parser.add_argument('--output',type=Path);parser.add_argument('--game',type=Path,default=project.parent);parser.add_argument('--embed',action='store_true');args=parser.parse_args()
    out=args.output or project/'data/releases'/('android-v'+args.version)
    if (project/'data/journal.json').exists():raise RuntimeError('Phục hồi giao dịch PC trước khi đóng gói.')
    source,build,report=Installer(project,args.game).build()
    overrides=source.overrides | {p.name:p for p in (build/'chunks').glob('*.ssrc')}
    target=Archive(source.root,build/'manifest.ssra',overrides)
    app=project/'czn_android_patcher' if (project/'czn_android_patcher').is_dir() else project
    key=app/'.signing/update-private.pk8'
    bundle,evidence=make_bundle(source,target,out,args.version,args.code,lambda raw:sign_metadata(raw,key))
    if args.embed:
        assets=app/'android/app/src/main/assets'
        (assets/'bundled.cznpatch').write_bytes(bundle.read_bytes())
        with zipfile.ZipFile(bundle) as z:(assets/'bundled-release.json').write_bytes(z.read('release.json'))
    print(json.dumps(evidence,ensure_ascii=False))
if __name__=='__main__':main()
