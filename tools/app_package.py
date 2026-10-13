"""Build the complete signed Android app for every translation release.

UI, icons, native code and the exact signed translation payload travel together.
No signing secrets are copied into release evidence or published assets.
"""
from __future__ import annotations
import hashlib,json,os,re,shutil,subprocess,zipfile
from pathlib import Path

PACKAGE='vn.czn.viethoa.community'
CERTIFICATE='5825ad2738d9ecc6f1ae685cf8122bf8d2e5814647540cd9876733762ccb3ab3'

def digest(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda:stream.read(1048576),b''):h.update(block)
    return h.hexdigest()

def app_root(home):
    home=Path(home).resolve()
    app=home/'czn_android_patcher' if (home/'czn_android_patcher').is_dir() else home
    if not (app/'pubspec.yaml').is_file():
        raise RuntimeError('Không có mã nguồn APK hiện hành. Khôi phục thư mục czn_android_patcher; không dùng lại APK cũ.')
    return app

def source_snapshot(app):
    app=Path(app)
    files={}
    for folder in ['lib','assets','android/app/src']:
        for path in (app/folder).rglob('*'):
            if path.is_file() and path.name!='GeneratedPluginRegistrant.java':
                files[path.relative_to(app).as_posix()]=digest(path)
    for name in ['pubspec.yaml','pubspec.lock','android/app/build.gradle.kts','android/app/proguard-rules.pro',
                 'android/build.gradle.kts','android/settings.gradle.kts','android/gradle.properties',
                 'android/gradle/wrapper/gradle-wrapper.properties']:
        path=app/name
        if path.is_file():files[name]=digest(path)
    if not files:raise RuntimeError('Snapshot mã nguồn APK rỗng.')
    return {'sha256':hashlib.sha256(json.dumps(files,sort_keys=True,separators=(',',':')).encode()).hexdigest(),'files':files}

def build_environment(app):
    properties={}
    path=app/'android/local.properties'
    if path.is_file():
        properties=dict(line.split('=',1) for line in path.read_text('utf-8-sig').splitlines() if '=' in line and not line.startswith('#'))
    def value(name):return properties.get(name,'').replace('\\\\','/').replace('\\:',':')
    flutter=Path(value('flutter.sdk'))/'bin'/('flutter.bat' if os.name=='nt' else 'flutter')
    if not flutter.is_file():
        located=shutil.which('flutter')
        if not located:raise RuntimeError('Cần Flutter SDK để dựng APK mới cùng bản dịch. Không phát hành chỉ bản dịch bằng APK cũ.')
        flutter=Path(located)
    sdk=Path(value('sdk.dir') or os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT',''))
    candidates=[]
    for folder in (sdk/'build-tools').glob('*'):
        if re.fullmatch(r'\d+\.\d+\.\d+',folder.name):candidates.append(folder)
    if not candidates:raise RuntimeError('Cần Android SDK build-tools để xác thực APK.')
    build_tools=max(candidates,key=lambda folder:tuple(map(int,folder.name.split('.'))))
    if not (app/'.signing/release.properties').is_file():raise RuntimeError('Thiếu khóa ký APK cộng đồng; không dựng APK không ký.')
    return flutter,build_tools

def inspect_apk(apk,build_tools):
    flags={'capture_output':True,'text':True,'check':True,'timeout':90,'creationflags':getattr(subprocess,'CREATE_NO_WINDOW',0)}
    badging=subprocess.run([str(build_tools/('aapt.exe' if os.name=='nt' else 'aapt')),'dump','badging',str(apk)],**flags).stdout
    match=re.search(r"package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'",badging)
    if not match or match[1]!=PACKAGE:raise RuntimeError('APK sai định danh ứng dụng CZN Việt Hóa.')
    cert=subprocess.run([str(build_tools/('apksigner.bat' if os.name=='nt' else 'apksigner')),'verify','--print-certs',str(apk)],**flags).stdout
    found=re.findall(r'certificate SHA-256 digest:\s*([0-9a-fA-F]+)',cert)
    if not found or any(item.lower()!=CERTIFICATE for item in found):raise RuntimeError('APK sai chứng thư cộng đồng; không thể nâng cấp bản đã cài.')
    return {'package':match[1],'version':match[3],'code':int(match[2]),'certificate_sha256':CERTIFICATE,'apk_sha256':digest(apk),'apk_size':Path(apk).stat().st_size}

def build_app(home,out,version,code,bundle=None,log=print):
    if not re.fullmatch(r'\d+\.\d+\.\d+',version) or not isinstance(code,int) or code<=0:raise ValueError('Phiên bản APK không hợp lệ.')
    app=app_root(home);out=Path(out)
    flutter,build_tools=build_environment(app)
    target=out/f'CZN_VietHoa_Android_v{version}.apk'
    if target.exists():raise FileExistsError('APK phiên bản này đã tồn tại; giữ lịch sử và chọn phiên bản mới.')
    out.mkdir(parents=True,exist_ok=True)
    saved={}
    assets=app/'android/app/src/main/assets'
    if bundle:
        from android_sync import verify_metadata
        bundle=Path(bundle)
        with zipfile.ZipFile(bundle) as archive:envelope=archive.read('release.json')
        verified=verify_metadata(envelope)
        if verified.get('schema')!=2 or not isinstance(verified.get('version_code'),int):raise RuntimeError('Bản dịch đi kèm không được ký đúng định dạng.')
        backup=out/'EMBEDDED_ASSETS_BEFORE';backup.mkdir()
        for name in ['bundled.cznpatch','bundled-release.json']:
            path=assets/name;saved[name]=path.read_bytes() if path.exists() else None
            if path.exists():shutil.copy2(path,backup/name)
        shutil.copy2(bundle,assets/'bundled.cznpatch');(assets/'bundled-release.json').write_bytes(envelope)
    try:
        before=source_snapshot(app)
        log(f'Đang dựng APK {version}: giao diện, icon, mã ứng dụng và bản dịch đi kèm. Chờ Flutter hoàn tất…')
        env=dict(os.environ)
        jbr=Path(os.environ.get('ProgramFiles','C:/Program Files'))/'Android/Android Studio/jbr'
        if not env.get('JAVA_HOME') and jbr.is_dir():env['JAVA_HOME']=str(jbr)
        with (out/'APP_BUILD.log').open('w',encoding='utf-8') as output:
            result=subprocess.run([str(flutter),'build','apk','--release','--build-name',version,'--build-number',str(code)],cwd=app,env=env,stdout=output,stderr=subprocess.STDOUT,timeout=1800,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        if result.returncode:raise RuntimeError('Build APK thất bại. Xem APP_BUILD.log; không phát hành gói thiếu APK mới.')
        after=source_snapshot(app)
        if before!=after:raise RuntimeError('Mã nguồn APK đổi trong lúc build; dựng lại trước khi phát hành.')
        built=app/'build/app/outputs/flutter-apk/app-release.apk'
        metadata=inspect_apk(built,build_tools)
        if metadata['version']!=version or metadata['code']!=code:raise RuntimeError('APK build không khớp phiên bản của gói cập nhật.')
        if bundle:
            with zipfile.ZipFile(built) as archive:
                if hashlib.sha256(archive.read('assets/bundled.cznpatch')).hexdigest()!=digest(bundle):raise RuntimeError('Bản dịch bên trong APK không khớp gói đã duyệt.')
        shutil.copy2(built,target)
        evidence={'schema':1,**metadata,'source':after,'full_app_update':True,'embedded_bundle_sha256':digest(assets/'bundled.cznpatch')}
        (out/'APP_BUILD_EVIDENCE.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2),encoding='utf-8')
        return target,evidence
    except BaseException:
        for name,content in saved.items():
            if content is not None:(assets/name).write_bytes(content)
            elif (assets/name).exists():(assets/name).unlink()
        raise

def assert_current_source(home,evidence):
    if not evidence.get('full_app_update') or source_snapshot(app_root(home))!=evidence.get('source'):
        raise RuntimeError('Mã nguồn/giao diện/icon APK đã đổi sau khi dựng. Dựng lại APK và gói cập nhật trước khi phát hành.')
