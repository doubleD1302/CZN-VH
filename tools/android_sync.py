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
    if not re.fullmatch(r'\d+\.\d+\.\d+',version):raise ValueError('Phiên bản phải có dạng 1.4.2.')
    major,minor,patch=map(int,version.split('.'))
    if minor>99 or patch>99:raise ValueError('Các phần phiên bản phụ phải từ 0 đến 99.')
    code=major*10000+minor*100+patch
    if code<10400 or code>2147483647:raise ValueError('Phiên bản không hợp lệ.')
    return code
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
    code=version_code(version)
    if (inst.data/'journal.json').exists():raise RuntimeError('Có giao dịch PC chưa hoàn tất. Phục hồi trước khi đồng bộ.')
    previous=check_updates()
    if code<=int(previous['patch_code']):raise ValueError('Chọn phiên bản cao hơn bản trên GitHub: '+previous['patch_version'])
    if len(title)>200 or len(body)>12000:raise ValueError('Thông báo quá dài.')
    if body.strip() and not title.strip():raise ValueError('Nhập tiêu đề thông báo.')
    key=Path(key)
    if not key.is_file():raise ValueError('Chọn khóa update-private.pk8. Khóa không được đưa vào gói phát hành.')
    out=inst.data/'releases'/('android-v'+version)
    if out.exists():raise FileExistsError('Thư mục phiên bản đã tồn tại. Giữ lịch sử và chọn phiên bản khác.')
    # Use the current catalog and original archive, never the Windows live translated slot.
    original,build,report=inst.build()
    target=Archive(original.root,build/'manifest.ssra',original.overrides | {p.name:p for p in (build/'chunks').glob('*.ssrc')})
    bundle,evidence=make_bundle(original,target,out,version,code,lambda raw:sign_metadata(raw,key))
    tag='android-v'+version;url=f'https://github.com/{REPO}/releases/download/{tag}/'
    channel={k:v for k,v in previous.items() if k.startswith('app_')}
    channel.update(schema=1,type='channel',patch_version=version,patch_code=code,patch_url=url+bundle.name,patch_size=bundle.stat().st_size,patch_sha256=digest(bundle),changelog=f"{evidence['text_changes']:,} mục văn bản và {evidence['story_changes']:,} câu JP đã đổi. "+body.strip())
    channel['notice']={'enabled':bool(body.strip()),'id':tag+'-'+uuid.uuid4().hex[:12],'title':title.strip(),'body':body.strip()}
    raw=out/'channel.descriptor.json';raw.write_text(json.dumps(channel,ensure_ascii=False,separators=(',',':')),encoding='utf-8');(out/'channel.json').write_bytes(sign_metadata(raw,key))
    if verify_metadata((out/'channel.json').read_bytes())!=channel:raise RuntimeError('Kênh ký không khớp bản dựng.')
    guide=out/'HUONG_DAN_ANDROID.txt';guide.write_text('Mở CZN Việt Hóa → Kiểm tra cập nhật → Cài tiếng Việt. Chọn 日本語 trong game. Khởi động Shizuku trước khi cài.\n'+body,encoding='utf-8')
    assets=[bundle,out/'channel.json',guide];sums=out/'SHA256SUMS.txt';sums.write_text(''.join(digest(f)+'  '+f.name+'\n' for f in assets),encoding='utf-8');assets.append(sums)
    record={'schema':1,'version':version,'code':code,'tag':tag,'directory':str(out),'asset_hashes':{f.name:digest(f) for f in assets},'evidence':evidence,'catalog_revision':report.get('catalog_revision'),'notice':channel['notice'],'app':{k:v for k,v in channel.items() if k.startswith('app_')},'gameplay':'pending_player'}
    (out/'SYNC_PREVIEW.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8');log('Đã dựng và xác thực gói. Chưa phát hành. Thư mục: '+str(out));return record

def publish(preview,token='',log=print):
    out=Path(preview['directory']);frozen=json.loads((out/'SYNC_PREVIEW.json').read_text('utf-8'))
    if frozen!=preview:raise RuntimeError('Bản chuẩn bị đã đổi. Dựng/duyệt lại trước khi phát hành.')
    allowed={f'CZN_Android_v{preview["version"]}.cznpatch','channel.json','HUONG_DAN_ANDROID.txt','SHA256SUMS.txt'}
    if set(preview['asset_hashes'])!=allowed:raise ValueError('Danh sách tài sản không hợp lệ.')
    for name,h in preview['asset_hashes'].items():
        if digest(out/name)!=h:raise RuntimeError('Tệp đã đổi sau kiểm tra: '+name)
    channel=verify_metadata((out/'channel.json').read_bytes())
    current=check_updates()
    if int(current['patch_code'])>=preview['code']:raise RuntimeError('GitHub đã có bản bằng/mới hơn. Chọn phiên bản mới.')
    if {k:v for k,v in current.items() if k.startswith('app_')}!=preview['app']:raise RuntimeError('APK trên GitHub đã đổi. Dựng lại để giữ đúng kênh cập nhật APK.')
    token=credentials(token);repo=api(token,'')
    if not repo.get('permissions',{}).get('push'):raise RuntimeError('Không có quyền phát hành vào kho CZN-VH.')
    release=None
    pending=out/'PUBLISH_STATE.json'
    try:
        existing=api(token,'/releases/tags/'+preview['tag'])
        saved=json.loads(pending.read_text('utf-8')) if pending.exists() else {}
        if not existing.get('draft') or saved.get('release_id')!=existing['id']:raise RuntimeError('Release đã tồn tại; không ghi đè.')
        release=existing
    except urllib.error.HTTPError as e:
        if e.code!=404:raise
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
    draft.update(state='published',url=release['html_url']);(out/'PUBLISH_STATE.json').write_text(json.dumps(draft,indent=2),encoding='utf-8');log('Đã phát hành: '+release['html_url']);return draft
