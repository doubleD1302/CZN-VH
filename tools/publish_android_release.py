"""Publish a concrete, verified Android release to the user's chosen GitHub repo.
Credential Manager tokens stay in memory; private signing material never leaves the workspace.
"""
import argparse,hashlib,json,os,subprocess,urllib.request,urllib.error
from pathlib import Path
P=Path(__file__).resolve().parents[1];APP=P/'czn_android_patcher' if (P/'czn_android_patcher').is_dir() else P

def digest(f):
 h=hashlib.sha256()
 with f.open('rb') as s:
  for b in iter(lambda:s.read(1048576),b''):h.update(b)
 return h.hexdigest()

def app_only_channel(previous,version,code,url,size,sha):
 if previous.get('schema')!=1 or previous.get('type')!='channel':raise ValueError('Invalid baseline channel')
 if code<=previous.get('app_code',0):raise ValueError('App update must have a higher version code')
 result=dict(previous)
 result.update(app_version=version,app_code=code,app_url=url,app_size=size,app_sha256=sha)
 return result
def credentials():
 env=dict(os.environ,GIT_TERMINAL_PROMPT='0',GCM_INTERACTIVE='Never')
 r=subprocess.run(['git','credential','fill'],input='protocol=https\nhost=github.com\n\n',text=True,capture_output=True,env=env,check=True,timeout=30)
 v=dict(line.split('=',1) for line in r.stdout.splitlines() if '=' in line)
 if not v.get('password'):raise RuntimeError('GitHub authentication unavailable')
 return v['password']
def api(token,url,method='GET',body=None,binary=False):
 headers={'User-Agent':'CZN-Community-Release','Authorization':'Bearer '+token,'Accept':'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28'}
 data=None
 if body is not None:
  if binary:data=body;headers['Content-Type']='application/octet-stream'
  else:data=json.dumps(body,ensure_ascii=False).encode('utf-8');headers['Content-Type']='application/json'
 with urllib.request.urlopen(urllib.request.Request(url,headers=headers,method=method,data=data),timeout=120) as response:return json.load(response)
def main():
 a=argparse.ArgumentParser();a.add_argument('--directory',type=Path,default=P/'data/releases/android-v1.4.0');a.add_argument('--version',default='1.4.0');a.add_argument('--code',type=int,default=10400);a.add_argument('--apk',type=Path);a.add_argument('--publish',action='store_true');a.add_argument('--notice',type=Path);a.add_argument('--pc-exe',type=Path);a.add_argument('--app-only',action='store_true');a.add_argument('--baseline-channel',type=Path);args=a.parse_args();out=args.directory
 apk=args.apk or out/f'CZN_VietHoa_Android_v{args.version}.apk';bundle=out/f'CZN_Android_v{args.version}.cznpatch';tag='android-v'+args.version;url=f'https://github.com/doubleD1302/CZN-VH/releases/download/{tag}/'
 import re
 sdk_props=(APP/'android/local.properties').read_text('utf-8-sig')
 sdk_line=next(x.split('=',1)[1] for x in sdk_props.splitlines() if x.startswith('sdk.dir='))
 sdk=Path(sdk_line.replace('\\\\','/'))
 aapt=sdk/'build-tools/36.0.0'/('aapt.exe' if os.name=='nt' else 'aapt')
 badging=subprocess.run([str(aapt),'dump','badging',str(apk)],capture_output=True,text=True,check=True).stdout
 match=re.search(r"package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'",badging)
 if not match or match.group(1)!='vn.czn.viethoa.community':raise RuntimeError('APK identity is not the community app')
 app_code=int(match.group(2));app_version=match.group(3)
 if args.app_only:
  from android_sync import verify_metadata,fetch,CHANNEL
  raw_baseline=args.baseline_channel.read_bytes() if args.baseline_channel else fetch(CHANNEL)
  previous=verify_metadata(raw_baseline)
  if app_version!=args.version or app_code!=args.code:raise ValueError('App-only tag/code must match the APK')
  channel=app_only_channel(previous,app_version,app_code,url+apk.name,apk.stat().st_size,digest(apk))
  (out/'BASELINE_CHANNEL.json').write_bytes(raw_baseline)
 else:
  channel=dict(schema=1,type='channel',patch_version=args.version,patch_code=args.code,patch_url=url+bundle.name,patch_size=bundle.stat().st_size,patch_sha256=digest(bundle),app_version=app_version,app_code=app_code,app_url=url+apk.name,app_size=apk.stat().st_size,app_sha256=digest(apk),changelog='Bản cộng đồng: cài qua Shizuku, backup/rollback, cập nhật có chữ ký và bản dịch JP đi kèm.')
 if args.notice:
  channel['notice']=json.loads(args.notice.read_text('utf-8'))
 raw=out/'channel.descriptor.json';raw.write_text(json.dumps(channel,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
 from android_sync import verify_metadata
 signed=out/'channel.json'
 if not signed.exists() or verify_metadata(signed.read_bytes())!=channel:
  subprocess.run(['pwsh','-NoProfile','-File',str(P/'tools/sign_android_metadata.ps1'),'-InputFile',str(raw),'-KeyFile',str(APP/'.signing/update-private.pk8'),'-OutputFile',str(signed)],check=True)
 if verify_metadata(signed.read_bytes())!=channel:raise RuntimeError('Signed channel differs from the prepared descriptor')
 assets=[apk]+([] if args.app_only else [bundle])+[out/'channel.json',out/'HUONG_DAN_ANDROID.txt']
 if args.pc_exe:
  if args.pc_exe.suffix.lower()!='.exe':raise ValueError('Only the PC executable may be added')
  assets.append(args.pc_exe)
 sums=out/'SHA256SUMS.txt';sums.write_text(''.join(digest(f)+'  '+f.name+'\n' for f in assets),encoding='utf-8');assets.append(sums)
 if not args.publish:print(json.dumps({'prepared':True,'assets':[f.name for f in assets],'tag':tag}));return
 # Require actual check results and a new release; never overwrite remote assets.
 evidence=json.loads((out/'FINAL_VERIFICATION.json').read_text('utf-8'))
 if not evidence.get('technical_checks_passed') or evidence.get('apk_sha256')!=digest(apk):raise RuntimeError('Release checks/hash snapshot not complete')
 if args.app_only:
  if not evidence.get('signed_baseline_patch_unchanged') or evidence.get('baseline_channel_sha256')!=digest(out/'BASELINE_CHANNEL.json'):raise RuntimeError('App-only baseline checks/hash snapshot not complete')
  if {k:v for k,v in previous.items() if k.startswith('patch_')}!={k:v for k,v in channel.items() if k.startswith('patch_')}:raise RuntimeError('App-only release changed patch metadata')
 elif evidence.get('bundle_sha256')!=digest(bundle):raise RuntimeError('Bundle hash snapshot not complete')
 token=credentials();base='https://api.github.com/repos/doubleD1302/CZN-VH'
 repo=api(token,base)
 if not repo.get('permissions',{}).get('push'):raise RuntimeError('No repository write permission')
 try:api(token,base+'/releases/tags/'+tag);raise RuntimeError('Release already exists; do not overwrite it')
 except urllib.error.HTTPError as e:
  if e.code!=404:raise
 notes=(out/'RELEASE_NOTES.txt').read_text('utf-8')
 release=api(token,base+'/releases',method='POST',body={'tag_name':tag,'target_commitish':evidence.get('source_commit','main'),'name':'CZN Android v'+args.version+' · Kiểm chứng cộng đồng','body':notes,'draft':True,'prerelease':False})
 (out/'PUBLISH_STATE.json').write_text(json.dumps({'id':release['id'],'tag':tag,'asset_hashes':{f.name:digest(f) for f in assets}},indent=2),encoding='utf-8')
 upload=release['upload_url'].split('{')[0]
 for f in assets:
  from urllib.parse import quote
  result=api(token,upload+'?name='+quote(f.name),method='POST',body=f.read_bytes(),binary=True)
  if result['size']!=f.stat().st_size or result.get('digest')!='sha256:'+digest(f):raise RuntimeError('Upload size/SHA256 mismatch')
 release=api(token,base+'/releases/'+str(release['id']),method='PATCH',body={'draft':False,'make_latest':'true'})
 record={'url':release['html_url'],'tag':tag,'id':release['id'],'assets':[{x['name']:x['browser_download_url']} for x in api(token,base+'/releases/'+str(release['id']))['assets']]}
 (out/'PUBLISHED_RELEASE.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps({'published':True,'url':record['url']}))
if __name__=='__main__':main()
