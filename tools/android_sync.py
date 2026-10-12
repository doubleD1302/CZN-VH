"""Maintainer-only Android publication, signed metadata; no credentials persisted."""
from __future__ import annotations
import base64,hashlib,json,os,re,shutil,subprocess,sys,tempfile,urllib.request,urllib.error,urllib.parse,uuid,zipfile
from pathlib import Path
REPO='doubleD1302/CZN-VH'
CHANNEL=f'https://github.com/{REPO}/releases/latest/download/channel.json'
def resource(name):
    if getattr(sys,'frozen',False):return Path(sys._MEIPASS)/name
    if name=='android_update_public.der':
        project=Path(__file__).resolve().parents[1];app=project/'czn_android_patcher' if (project/'czn_android_patcher').is_dir() else project
        return app/'android/app/src/main/assets/update-public.der'
    return Path(__file__).with_name(name)
def _crypto(mode,input_file,output_file,key=None):
    pwsh=shutil.which('pwsh')
    if not pwsh:raise RuntimeError('Cần PowerShell 7 để ký/xác thực cập nhật. Cài từ https://github.com/PowerShell/PowerShell/releases rồi mở lại bộ cài.')
    args=[pwsh,'-NoProfile','-File',str(resource('android_metadata_crypto.ps1')),'-Mode',mode,'-InputFile',str(input_file),'-PublicFile',str(resource('android_update_public.der')),'-OutputFile',str(output_file)]
    if key:args+=['-KeyFile',str(key)]
    result=subprocess.run(args,capture_output=True,timeout=30,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    if result.returncode:raise RuntimeError('Ký/xác thực thất bại. Kiểm tra đúng khóa cập nhật của dự án; không phát hành dữ liệu chưa xác thực.')
def sign_metadata(raw,key):
    result=Path(raw).with_suffix('.signed.json');_crypto('Sign',raw,result,key);return result.read_bytes()
def verify_metadata(envelope):
    if len(envelope)>262144:raise ValueError('Metadata quá lớn.')
    with tempfile.TemporaryDirectory(prefix='czn-channel-') as temp:
        raw=Path(temp)/'envelope.json';out=Path(temp)/'verified.json';raw.write_bytes(envelope);_crypto('Verify',raw,out);return json.loads(out.read_text('utf-8'))
def fetch(url,limit=262144):
    if urllib.parse.urlparse(url).scheme!='https':raise ValueError('Chỉ dùng HTTPS.')
    with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'CZN-Maintainer/1.3.1'}),timeout=30) as r:
        if urllib.parse.urlparse(r.url).scheme!='https':raise ValueError('Chuyển hướng không dùng HTTPS.')
        data=r.read(limit+1)
    if len(data)>limit:raise ValueError('Dữ liệu tải vượt giới hạn.')
    return data
def check_updates():
    envelope=fetch(CHANNEL);data=verify_metadata(envelope)
    if data.get('schema')!=1 or data.get('type')!='channel':raise ValueError('Kênh cập nhật sai định dạng.')
    return data
def version_code(version):
    version=normalize_version(version)
    major,minor,patch=map(int,version.split('.'))
    if minor>99 or patch>99:raise ValueError('Các phần phiên bản phụ phải từ 0 đến 99.')
    code=major*10000+minor*100+patch
    if code<10400:raise ValueError('Phiên bản tối thiểu là 1.4.0. Hãy chọn số mới hơn bản dịch đã phát hành.')
    if code>2147483647:raise ValueError('Phiên bản vượt giới hạn Android.')
    return code

def normalize_version(version):
    value=version.strip()
    if len(value)>40:raise ValueError('Phiên bản quá dài.')
    match=re.fullmatch(r'[vV]?([0-9]+)\.([0-9]+)(?:\.([0-9]+))?\.?',value)
    if not match:raise ValueError('Nhập phiên bản bằng số, ví dụ 1.5 hoặc 1.5.0. Có thể thêm v hoặc một dấu chấm cuối.')
    major,minor,patch=(int(match[1]),int(match[2]),int(match[3] or 0))
    if minor>99 or patch>99:raise ValueError('Số thứ hai và thứ ba phải từ 0 đến 99, ví dụ 1.5.0.')
    return f'{major}.{minor}.{patch}'

def suggested_version(channel):
    code=max(int(channel['patch_code']),int(channel.get('app_code',0)))+1
    return f'{code//10000}.{code//100%100}.{code%100}'

def validate_new_version(version,previous):
    version=normalize_version(version);code=version_code(version)
    if code<=int(previous['patch_code']):
        raise ValueError(f"Bản dịch {version} phải cao hơn {previous['patch_version']} đã phát hành. Gợi ý: {suggested_version(previous)}.")
    # APK and translation releases share tags. An app-only tag can already be taken.
    try:
        fetch(f'https://api.github.com/repos/{REPO}/releases/tags/android-v{version}')
    except urllib.error.HTTPError as error:
        if error.code!=404:raise
    else:
        raise ValueError(f'Phiên bản {version} đã có release trên GitHub. Chọn số khác, ví dụ {suggested_version(previous)}; lịch sử cũ được giữ lại.')
    return version,code
def digest(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as f:
        for b in iter(lambda:f.read(1048576),b''):h.update(b)
    return h.hexdigest()
def credentials(explicit=''):
    if explicit:return explicit
    env=dict(os.environ,GIT_TERMINAL_PROMPT='0',GCM_INTERACTIVE='Never')
    result=subprocess.run(['git','credential','fill'],input='protocol=https\nhost=github.com\n\n',text=True,capture_output=True,timeout=30,env=env,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    if result.returncode:raise RuntimeError('Chưa đăng nhập GitHub. Nhập token có quyền Contents: Read and write cho kho CZN-VH.')
    values=dict(line.split('=',1) for line in result.stdout.splitlines() if '=' in line)
    if not values.get('password'):raise RuntimeError('Chưa có token GitHub.')
    return values['password']
def api(token,path,method='GET',body=None,binary=False):
    url=path if path.startswith('https://') else f'https://api.github.com/repos/{REPO}'+path
    headers={'Authorization':'Bearer '+token,'User-Agent':'CZN-Maintainer','Accept':'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28'}
    data=None
    if body is not None:
        data=body if binary else json.dumps(body,ensure_ascii=False).encode('utf-8');headers['Content-Type']='application/octet-stream' if binary else 'application/json'
    try:
        with urllib.request.urlopen(urllib.request.Request(url,headers=headers,data=data,method=method),timeout=120) as r:return json.load(r)
    except urllib.error.HTTPError as e:
        if e.code in (401,403):raise RuntimeError('GitHub từ chối quyền. Token cần quyền Contents: Read and write cho đúng kho.') from None
        raise

def prepare(inst,version,title,body,key,log=print):
    from czn_format import Archive
    from package_android_patch import make_bundle
    from change_history import capture,ensure_baseline,changes_since_publication,notice_text
    version=normalize_version(version);code=version_code(version)
    if (inst.data/'journal.json').exists():raise RuntimeError('Có giao dịch PC chưa hoàn tất. Phục hồi trước khi đồng bộ.')
    previous=check_updates()
    version,code=validate_new_version(version,previous)
    if len(title)>200 or len(body)>12000:raise ValueError('Thông báo quá dài.')
    if body.strip() and not title.strip():raise ValueError('Nhập tiêu đề thông báo.')
    key=Path(key)
    if not key.is_file():raise ValueError('Chọn khóa update-private.pk8. Khóa không được đưa vào gói phát hành.')
    out=inst.data/'releases'/('android-v'+version)
    if out.exists():raise FileExistsError('Thư mục phiên bản đã tồn tại. Giữ lịch sử và chọn phiên bản khác.')
    capture(inst.home)
    ensure_baseline(inst.home,previous)
    # Use the current catalog and original archive, never the Windows live translated slot.
    original,build,report=inst.build()
    target=Archive(original.root,build/'manifest.ssra',original.overrides | {p.name:p for p in (build/'chunks').glob('*.ssrc')})
    bundle,evidence=make_bundle(original,target,out,version,code,lambda raw:sign_metadata(raw,key))
    snapshot=json.loads((out/'TRANSLATION_SNAPSHOT.json').read_text('utf-8'))
    delta=changes_since_publication(inst.home,snapshot)
    automatic=notice_text(delta)
    title=title.strip() or 'CZN Việt Hóa có bản cập nhật'
    body=automatic+('\n\n'+body.strip() if body.strip() else '')
    if len(body)>12000:raise ValueError('Thông báo gồm phần tự điền và ghi chú vượt 12.000 ký tự; rút gọn ghi chú rồi chọn phiên bản mới.')
    (out/'UNPUBLISHED_CHANGES.json').write_text(json.dumps(delta,ensure_ascii=False,indent=2),encoding='utf-8')
    tag='android-v'+version;url=f'https://github.com/{REPO}/releases/download/{tag}/'
    channel={k:v for k,v in previous.items() if k.startswith('app_')}
    channel.update(schema=1,type='channel',patch_version=version,patch_code=code,patch_url=url+bundle.name,patch_size=bundle.stat().st_size,patch_sha256=digest(bundle),changelog=body.strip())
    channel['notice']={'enabled':bool(body.strip()),'id':tag+'-'+uuid.uuid4().hex[:12],'title':title.strip(),'body':body.strip()}
    raw=out/'channel.descriptor.json';raw.write_text(json.dumps(channel,ensure_ascii=False,separators=(',',':')),encoding='utf-8');(out/'channel.json').write_bytes(sign_metadata(raw,key))
    if verify_metadata((out/'channel.json').read_bytes())!=channel:raise RuntimeError('Kênh ký không khớp bản dựng.')
    guide=out/'HUONG_DAN_ANDROID.txt';guide.write_text('Mở CZN Việt Hóa → Kiểm tra cập nhật → Cài tiếng Việt. Chọn 日本語 trong game. Khởi động Shizuku trước khi cài.\n'+body,encoding='utf-8')
    assets=[bundle,out/'channel.json',guide];sums=out/'SHA256SUMS.txt';sums.write_text(''.join(digest(f)+'  '+f.name+'\n' for f in assets),encoding='utf-8');assets.append(sums)
    record={'schema':1,'version':version,'code':code,'tag':tag,'directory':str(out),'asset_hashes':{f.name:digest(f) for f in assets},'evidence':evidence,'catalog_revision':report.get('catalog_revision'),'notice':channel['notice'],'automatic_notice':automatic,'unpublished_count':len(delta['changes']),'home':str(inst.home),'translation_snapshot_sha256':digest(out/'TRANSLATION_SNAPSHOT.json'),'unpublished_changes_sha256':digest(out/'UNPUBLISHED_CHANGES.json'),'app':{k:v for k,v in channel.items() if k.startswith('app_')},'gameplay':'pending_player'}
    (out/'SYNC_PREVIEW.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8');log('Đã dựng và xác thực gói. Chưa phát hành. Thư mục: '+str(out));return record

def draft_for(token,preview,out):
    pending=out/'PUBLISH_STATE.json'
    if pending.exists():
        saved=json.loads(pending.read_text('utf-8'));identity=saved.get('release_id')
        if not isinstance(identity,int) or identity<=0:raise RuntimeError('ID bản nháp không hợp lệ.')
        existing=api(token,'/releases/'+str(identity))
        if not existing.get('draft') or existing.get('tag_name')!=preview['tag']:raise RuntimeError('Bản nháp đã đổi/đã công khai. Kiểm tra trạng thái trước khi phát hành tiếp.')
        return existing
    try:
        api(token,'/releases/tags/'+preview['tag'])
        raise RuntimeError('Release đã tồn tại; không ghi đè.')
    except urllib.error.HTTPError as e:
        if e.code!=404:raise
    return None

def publish(preview,token='',log=print):
    out=Path(preview['directory']);frozen=json.loads((out/'SYNC_PREVIEW.json').read_text('utf-8'))
    if frozen!=preview:raise RuntimeError('Bản chuẩn bị đã đổi. Dựng/duyệt lại trước khi phát hành.')
    allowed={f'CZN_Android_v{preview["version"]}.cznpatch','channel.json','HUONG_DAN_ANDROID.txt','SHA256SUMS.txt'}
    if set(preview['asset_hashes'])!=allowed:raise ValueError('Danh sách tài sản không hợp lệ.')
    for name,h in preview['asset_hashes'].items():
        if digest(out/name)!=h:raise RuntimeError('Tệp đã đổi sau kiểm tra: '+name)
    if 'translation_snapshot_sha256' not in preview:raise RuntimeError('Gói được chuẩn bị bằng công cụ cũ. Dựng lại để có dấu vết bản dịch.')
    for name,field in [('TRANSLATION_SNAPSHOT.json','translation_snapshot_sha256'),('UNPUBLISHED_CHANGES.json','unpublished_changes_sha256')]:
        if digest(out/name)!=preview[field]:raise RuntimeError('Dấu vết gói đã đổi; dựng/duyệt lại trước khi phát hành.')
    channel=verify_metadata((out/'channel.json').read_bytes())
    current=check_updates()
    saved=json.loads((out/'PUBLISH_STATE.json').read_text('utf-8')) if (out/'PUBLISH_STATE.json').exists() else {}
    if int(current['patch_code'])==preview['code'] and current['patch_sha256']==channel['patch_sha256'] and saved.get('release_id'):
        # Retry after promotion/verification interruption: no second release or upload.
        token=credentials(token)
        receipt=finalize_publication(preview,channel,saved['release_id'],token)
        saved.update(state='verified',receipt=receipt)
        (out/'PUBLISH_STATE.json').write_text(json.dumps(saved,ensure_ascii=False,indent=2),encoding='utf-8')
        log('Đã xác thực phát hành và lưu dấu vết: '+saved['url']);return saved
    if int(current['patch_code'])>=preview['code']:raise RuntimeError('GitHub đã có bản bằng/mới hơn. Chọn phiên bản mới.')
    if {k:v for k,v in current.items() if k.startswith('app_')}!=preview['app']:raise RuntimeError('APK trên GitHub đã đổi. Dựng lại để giữ đúng kênh cập nhật APK.')
    token=credentials(token);repo=api(token,'')
    if not repo.get('permissions',{}).get('push'):raise RuntimeError('Không có quyền phát hành vào kho CZN-VH.')
    release=draft_for(token,preview,out)
    notes=f"Cập nhật bản dịch {preview['version']}.\n\n"+channel.get('changelog','')+'\n\nGói JP có chữ ký, kiểm tra native/token/byte ngoài slot. Gameplay điện thoại chờ người chơi kiểm chứng.'
    if release is None:release=api(token,'/releases','POST',{'tag_name':preview['tag'],'target_commitish':'main','name':'CZN Android · Bản dịch '+preview['version'],'body':notes,'draft':True,'prerelease':False})
    # Keep the ID immediately: failed upload remains a recoverable draft, not a public incomplete channel.
    draft={'release_id':release['id'],'url':release['html_url'],'state':'uploading'}
    (out/'PUBLISH_STATE.json').write_text(json.dumps(draft,indent=2),encoding='utf-8')
    upload=release['upload_url'].split('{')[0]
    for name in preview['asset_hashes']:
        f=out/name
        existing_asset=next((a for a in release.get('assets',[]) if a['name']==name),None)
        if existing_asset:
            if existing_asset.get('size')!=f.stat().st_size or existing_asset.get('digest')!='sha256:'+digest(f):raise RuntimeError('Tài sản trong draft không khớp; giữ draft để kiểm tra.')
            log('Đã có tài sản đúng hash: '+name);continue
        log('Đang tải lên: '+name)
        result=api(token,upload+'?name='+urllib.parse.quote(name),'POST',f.read_bytes(),True)
        if result['size']!=f.stat().st_size or result.get('digest') not in (None,'sha256:'+digest(f)):raise RuntimeError('GitHub trả checksum/kích thước không khớp.')
    release=api(token,'/releases/'+str(release['id']),'PATCH',{'draft':False,'make_latest':'true'})
    draft.update(state='published',url=release['html_url']);(out/'PUBLISH_STATE.json').write_text(json.dumps(draft,indent=2),encoding='utf-8')
    try:receipt=finalize_publication(preview,channel,release['id'],token)
    except Exception as error:
        raise RuntimeError('Release đã công khai nhưng chưa xác thực xong dấu vết. Các mục vẫn chờ; bấm Phát hành lại để kiểm tra tiếp. '+str(error)) from error
    draft.update(state='verified',receipt=receipt);(out/'PUBLISH_STATE.json').write_text(json.dumps(draft,ensure_ascii=False,indent=2),encoding='utf-8');log('Đã phát hành và xác thực: '+release['html_url']);return draft

def finalize_publication(preview,channel,release_id,token):
    from change_history import acknowledge
    out=Path(preview['directory'])
    public=check_updates()
    if public!=channel:raise RuntimeError('Kênh công khai chưa khớp kênh đã ký; giữ các mục chờ.')
    release=api(token,'/releases/'+str(release_id))
    if release.get('draft') or release.get('prerelease') or release.get('tag_name')!=preview['tag']:
        raise RuntimeError('Release chưa công khai đúng tag.')
    assets={a['name']:a for a in release.get('assets',[])}
    for name,h in preview['asset_hashes'].items():
        asset=assets.get(name,{})
        if asset.get('digest')!='sha256:'+h or asset.get('size')!=(out/name).stat().st_size:
            raise RuntimeError('Tài sản công khai chưa khớp SHA-256/kích thước: '+name)
    snapshot_path=out/'TRANSLATION_SNAPSHOT.json'
    if digest(snapshot_path)!=preview['translation_snapshot_sha256']:raise RuntimeError('Snapshot bản dịch đã đổi.')
    receipt={'public_verified':True,'release_id':release_id,'url':release['html_url'],
             'bundle_sha256':channel['patch_sha256'],'snapshot_sha256':digest(snapshot_path),'asset_hashes':preview['asset_hashes']}
    acknowledge(Path(preview['home']),json.loads(snapshot_path.read_text('utf-8')),channel,receipt)
    return receipt
