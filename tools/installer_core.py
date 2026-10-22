from __future__ import annotations
import csv
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import time
import uuid

from czn_format import Archive, Database, FormatError, MissingChunkError, validate_translation, xxhash

VERSION = '1.3.6'
IDENTITY_FILES = ('manifest.ssra.etag', 'manifest.ssra.prev')
LEGACY_MANIFESTS = {
    '45a0093589720c98ac0e9b91bd711f26ce34b74d0d5db4fe21f21aa141edce15',
    'd13bd891fbf948e343dce70283dba661561826ddcac3df1e9c8dfbf5bc8d7f21',
}


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def atomic_bytes(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    def signature():
        if not path.exists():
            return None
        info = path.stat()
        return info.st_ino, info.st_size, info.st_mtime_ns
    before = signature()
    temp = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    try:
        with temp.open('wb') as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        if os.name == 'nt' and path.exists():
            # ReplaceFile preserves the existing DACL and filesystem attributes.
            import ctypes
            api = ctypes.WinDLL('kernel32', use_last_error=True)
            replace = api.ReplaceFileW
            replace.argtypes = [ctypes.c_wchar_p, ctypes.c_wchar_p, ctypes.c_wchar_p,
                                ctypes.c_ulong, ctypes.c_void_p, ctypes.c_void_p]
            replace.restype = ctypes.c_int
            for attempt in range(8):
                if signature() != before:
                    raise RuntimeError('File thay đổi trong lúc chuẩn bị ghi: ' + str(path))
                if replace(str(path.resolve()), str(temp.resolve()), None, 0, None, None):
                    break
                code = ctypes.get_last_error()
                # These failures retain both original names. Antivirus or a
                # read-only status poll can hold a brief non-delete-sharing handle.
                # Never retry move/partial-rename errors, and never weaken ACLs.
                if code not in (32, 33, 1175) or attempt == 7:
                    error = ctypes.WinError(code)
                    error.filename = str(path)
                    raise error
                time.sleep(0.25)
        else:
            if signature() != before:
                raise RuntimeError('File thay đổi trong lúc chuẩn bị ghi: ' + str(path))
            os.replace(temp, path)
    finally:
        if temp.exists():
            temp.unlink()


def write_json(path, data):
    from change_history import tracked_write
    tracked_write(path, json.dumps(data, ensure_ascii=False, indent=2).encode('utf-8'), atomic_bytes)


def read_json(path, default=None):
    if not Path(path).exists():
        return default
    return json.loads(Path(path).read_text('utf-8-sig'))


def contained(root, relative):
    root = Path(root).resolve()
    target = (root / relative).resolve()
    if root not in target.parents:
        raise ValueError('Đường dẫn dữ liệu vượt ra ngoài thư mục cho phép.')
    return target


ALLOWED_BASE_CHUNKS = {f'chunks/base_b{i:02d}_0.ssrc' for i in range(1, 64)}


def allowed_resource(relative):
    p = Path(relative)
    return relative in (
        'manifest.ssra', *IDENTITY_FILES, *ALLOWED_BASE_CHUNKS
    ) or (
        len(p.parts) == 2 and p.parts[0] == 'chunks' and p.name.startswith('lang_ja_') and p.suffix == '.ssrc'
    )


def manifest_identity(existing, manifest):
    """Preserve the remote URL/ETag and synchronize the local cache fingerprint."""
    if b'\r\n' not in existing:
        raise FormatError('File nhận diện manifest không có định dạng CRLF được hỗ trợ.')
    lines = existing.split(b'\r\n')
    if len(lines) < 4 or not lines[0].startswith((b'https://', b'http://')) or not lines[2].isdigit() or not lines[3].isdigit():
        raise FormatError('File nhận diện manifest không hợp lệ; hãy hoàn tất cập nhật game trước.')
    lines[2] = str(xxhash.xxh64(manifest).intdigest()).encode('ascii')
    lines[3] = str(len(manifest)).encode('ascii')
    return b'\r\n'.join(lines)


def require_game_closed():
    if os.name != 'nt':
        return
    result = subprocess.run(['tasklist', '/FO', 'CSV', '/NH'], capture_output=True,
                            creationflags=subprocess.CREATE_NO_WINDOW, check=True)
    text = result.stdout.decode('utf-8', errors='replace').lower()
    if 'ucldr_chaoszeronightmare' in text:
        raise RuntimeError('Game đang chạy. Hãy thoát game rồi thực hiện lại.')
    if 'ssr-stove-shield.exe' in text:
        raise RuntimeError('Tiến trình game/STOVE chưa đóng hoàn toàn. Hãy thoát game và STOVE rồi thực hiện lại.')



def check_write_access(paths):
    if os.name != 'nt':
        return
    import ctypes
    api = ctypes.WinDLL('kernel32', use_last_error=True)
    create = api.CreateFileW
    create.argtypes = [ctypes.c_wchar_p, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_void_p,
                       ctypes.c_ulong, ctypes.c_ulong, ctypes.c_void_p]
    create.restype = ctypes.c_void_p
    api.CloseHandle.argtypes = [ctypes.c_void_p]
    invalid = ctypes.c_void_p(-1).value
    for path in paths:
        handle = create(str(Path(path).resolve()), 0x40010000, 7, None, 3, 0x80, None)
        if handle == invalid:
            code = ctypes.get_last_error()
            if code == 5:
                raise PermissionError('Windows yêu cầu quyền Administrator để ghi file game. Cho phép UAC khi bộ cài yêu cầu hoặc chạy EXE bằng Run as administrator.')
            raise ctypes.WinError(code)
        api.CloseHandle(handle)


class Installer:
    def __init__(self, project_dir, game_dir, log=print):
        self.home = Path(project_dir).resolve()
        self.data = self.home / 'data'
        self.data.mkdir(parents=True, exist_ok=True)
        self.game = Path(game_dir).resolve()
        self.resources = self.game / 'bin/appdata/cznlive/gameres'
        if not (self.resources / 'manifest.ssra').is_file():
            raise ValueError('Không tìm thấy game tại thư mục đã chọn (thiếu bin/appdata/cznlive/gameres/manifest.ssra).')
        self.log = log
        self.state_file = self.data / 'state.json'
        self.journal_file = self.data / 'journal.json'
        self.catalog_file = self.data / 'translations.json'
        self.snapshot_file = self.data / 'snapshot.json.gz'
        self.state = read_json(self.state_file, {})
        if self.state and Path(self.state['game_dir']).resolve() != self.game:
            raise ValueError('Bộ cài này đang quản lý một thư mục game khác. Hãy sao chép bộ cài sang thư mục mới để quản lý riêng.')

    def _backup_dir(self, state=None):
        state = self.state if state is None else state
        return contained(self.data, state['backup'])

    def status(self):
        """Read actual game files; a successful past install is not current status."""
        state = read_json(self.state_file, {})
        result = {'version': VERSION, 'installed': False, 'mode': 'not_installed',
                  'message': 'Chưa cài Việt hóa.', 'files': {}}
        if self.journal_file.exists():
            return result | {'mode': 'interrupted', 'message': 'Có thao tác bị gián đoạn; cần phục hồi trước.'}
        if not state.get('installed'):
            return result
        if Path(state['game_dir']).resolve() != self.game:
            raise ValueError('Trạng thái thuộc thư mục game khác.')
        resource_hashes = {rel: digest for rel, digest in state['patched_hashes'].items() if rel not in IDENTITY_FILES}
        for rel, digest in resource_hashes.items():
            if not allowed_resource(rel):
                raise ValueError('Trạng thái có đường dẫn không hợp lệ.')
            path = contained(self.resources, rel)
            actual = sha(path) if path.is_file() else None
            result['files'][rel] = {'sha256': actual, 'patched': actual == digest,
                                   'original': actual == state['original_hashes'].get(rel)}
        if all(row['patched'] for row in result['files'].values()):
            etag = self.resources / IDENTITY_FILES[0]
            if etag.exists():
                current = etag.read_bytes()
                if manifest_identity(current, (self.resources / 'manifest.ssra').read_bytes()) != current:
                    return result | {'mode': 'identity_mismatch', 'message': 'Đã ghi chữ Việt nhưng dấu nhận diện chưa khớp; game có thể tải lại bản Nhật.'}
            return result | {'installed': True, 'mode': 'installed', 'message': 'File Việt hóa và dấu nhận diện hiện còn khớp.'}
        if all(row['original'] for row in result['files'].values()):
            return result | {'mode': 'reverted', 'message': 'Game đã khôi phục file Nhật gốc; bản Việt hóa hiện không còn được cài.'}
        return result | {'mode': 'changed', 'message': 'File game đã thay đổi hoặc đang cập nhật; cần kiểm tra và đồng bộ lại.'}

    def recover(self):
        journal = read_json(self.journal_file)
        if not journal:
            return
        if Path(journal['game_dir']).resolve() != self.game:
            raise RuntimeError('Có thao tác chưa hoàn tất cho thư mục game khác.')
        txn = contained(self.data, journal['transaction'])
        previous = journal['previous_hashes']
        # Do not overwrite a subsequent official game update with an interrupted transaction.
        for rel, digest in previous.items():
            if not allowed_resource(rel):
                raise ValueError('Nhật ký có đường dẫn không hợp lệ.')
            old = contained(txn, rel)
            target = contained(self.resources, rel)
            current = sha(target)
            if sha(old) != digest or current not in (digest, journal['next_hashes'][rel]):
                raise RuntimeError('Game đã thay đổi sau thao tác gián đoạn. Hãy kiểm tra file bằng STOVE trước; bộ cài không ghi đè phiên bản mới.')
        self.log('Phục hồi thao tác bị gián đoạn...')
        changed_files = [rel for rel in previous if sha(contained(self.resources, rel)) != previous[rel]]
        check_write_access(contained(self.resources, rel) for rel in changed_files)
        for rel in changed_files:
            atomic_bytes(contained(self.resources, rel), contained(txn, rel).read_bytes())
        if journal['previous_state']:
            write_json(self.state_file, journal['previous_state'])
        elif self.state_file.exists():
            self.state_file.unlink()
        self.state = journal['previous_state'] or {}
        self.journal_file.unlink()

    def original_archive(self):
        self.recover()
        current_manifest = sha(self.resources / 'manifest.ssra')
        if self.state.get('installed') and current_manifest == self.state['patched_hashes']['manifest.ssra']:
            for rel, digest in self.state['patched_hashes'].items():
                if rel in IDENTITY_FILES:
                    continue
                if not allowed_resource(rel) or sha(contained(self.resources, rel)) != digest:
                    raise RuntimeError('Bản vá đang cài bị thay đổi hoặc game cập nhật chưa hoàn tất. Hãy hoàn tất kiểm tra file bằng STOVE trước.')
            backup = self._backup_dir()
            for rel, digest in self.state['original_hashes'].items():
                if not allowed_resource(rel) or sha(contained(backup, rel)) != digest:
                    raise RuntimeError('Bản sao lưu không còn đúng checksum.')
            overrides = {Path(rel).name: contained(backup, rel) for rel in self.state['original_hashes'] if rel != 'manifest.ssra'}
            ar = Archive(self.resources, backup / 'manifest.ssra', overrides)
        else:
            ar = Archive(self.resources)
            # An update can keep an unchanged, previously patched language chunk.
            if self.state.get('installed'):
                backup = self._backup_dir()
                for c in ar.chunks:
                    rel = 'chunks/' + c['name']
                    if rel in self.state['patched_hashes'] and (self.resources / rel).exists() and sha(self.resources / rel) == self.state['patched_hashes'][rel]:
                        original = contained(backup, rel)
                        if sha(original) != self.state['original_hashes'][rel]:
                            raise RuntimeError('Bản sao lưu chunk không còn đúng checksum.')
                        # Archive.chunk_bytes verifies this backup matches the NEW manifest.
                        ar.overrides[c['name']] = original
        try:
            db = Database(ar.read_file('text/ja/text.db'))
        except (FormatError, FileNotFoundError):
            if current_manifest not in LEGACY_MANIFESTS or self.state:
                raise
            backup_manifest = self.resources / 'manifest.ssra.bak'
            if not backup_manifest.exists() or sha(backup_manifest) != '45a0093589720c98ac0e9b91bd711f26ce34b74d0d5db4fe21f21aa141edce15':
                raise
            overrides = {p.name[:-4]: p for p in (self.resources / 'chunks').glob('lang_ja_*.ssrc.bak')}
            ar = Archive(self.resources, backup_manifest, overrides)
            db = Database(ar.read_file('text/ja/text.db'))
            self.log('Đã xác minh bản sao lưu gốc của bộ cài cũ; sẽ dựng lại bản vá.')
        return ar, db

    def catalog(self):
        data = read_json(self.catalog_file)
        if not isinstance(data, dict) or data.get('schema') != 1 or not isinstance(data.get('entries'), list):
            raise ValueError('Thiếu hoặc sai định dạng data/translations.json.')
        seen = set()
        for r in data['entries']:
            if r['id'] in seen:
                raise ValueError('Bản dịch có ID trùng: ' + r['id'])
            seen.add(r['id'])
        return data

    def snapshot(self):
        if not self.snapshot_file.exists():
            return {}
        return json.loads(gzip.decompress(self.snapshot_file.read_bytes()))

    def sync(self):
        file_status = self.status()
        if self.state.get('installed') and not file_status['installed']:
            self.log(file_status['message'])
        ar, db = self.original_archive()
        catalog = self.catalog()
        by_id = {x['id']: x for x in catalog['entries']}
        previous = self.snapshot()
        previous_texts = previous.get('texts', {})
        fingerprint = hashlib.sha256(ar.data).hexdigest()
        same_version = previous.get('manifest_sha256') == fingerprint
        changed_ids = set(previous.get('changed_ids', [])) if same_version else {
            key for key in db.order if previous_texts.get(key) != db.texts[key]
        }
        accepted, issues, pending, changed = {}, [], [], []
        self.log(f'Đọc được {db.rows:,} mục tiếng Nhật. Đang đối chiếu bản dịch...')
        en = {}
        if 'text/en/text.db' in ar.files:
            try:
                en = Database(ar.read_file('text/en/text.db')).texts
            except (FormatError, FileNotFoundError, MissingChunkError):
                self.log('Không có bản tiếng Anh hợp lệ để đối chiếu; tiếp tục với nguồn Nhật.')
        for key in db.order:
            ja = db.texts[key]
            r = by_id.get(key, {})
            why = ''
            if r:
                if r.get('source_ja') != ja:
                    why = 'Nguồn Nhật đã thay đổi; cần dịch lại'
                else:
                    why = validate_translation(ja, r.get('text_vi', '')) or ''
                    if not why:
                        accepted[key] = r['text_vi']
            else:
                why = 'Chưa dịch'
            row = {'id': key, 'text_ja': ja, 'text_en': en.get(key, r.get('text_en', '')),
                   'text_vi': accepted.get(key, ''), 'category': r.get('category', ''),
                   'reason': why, 'previous_ja': r.get('source_ja', previous_texts.get(key, '')),
                   'previous_vi': r.get('text_vi', '')}
            if why:
                pending.append(row)
                if r:
                    issues.append(row)
            if key in changed_ids and why:
                changed.append(row)
        removed = sorted(set(by_id) - db.texts.keys())
        report = {'installer_version': VERSION, 'manifest_sha256': fingerprint, 'rows': db.rows,
                  'ready': len(accepted), 'pending': len(pending), 'needs_review': len(issues),
                  'new_or_changed': len(changed), 'removed_ids': len(removed), 'removed_examples': removed[:20],
                  'catalog_revision': catalog.get('revision', ''), 'time': time.strftime('%Y-%m-%d %H:%M:%S'),
                  'file_status': file_status}
        from story_localization import build_story
        _, report['story'] = build_story(ar, self.home)
        reports = self.data / 'reports'
        reports.mkdir(parents=True, exist_ok=True)
        fields = ['id', 'text_ja', 'text_en', 'text_vi', 'category', 'reason', 'previous_ja', 'previous_vi']
        for name, rows in [('CHO_DICH.csv', pending), ('CAN_DICH_MOI.csv', changed), ('CAN_SUA.csv', issues)]:
            temp = reports / (name + '.tmp')
            with temp.open('w', encoding='utf-8-sig', newline='') as f:
                writer = csv.DictWriter(f, fieldnames=fields)
                writer.writeheader()
                writer.writerows(rows)
            os.replace(temp, reports / name)
        write_json(reports / 'TRANG_THAI.json', report)
        report_name = time.strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:6] + '.json'
        write_json(reports / 'history' / report_name, report)
        snapshot = {'schema': 1, 'manifest_sha256': fingerprint, 'texts': db.texts,
                    'changed_ids': sorted(changed_ids)}
        atomic_bytes(self.snapshot_file, gzip.compress(json.dumps(snapshot, ensure_ascii=False).encode('utf-8')))
        self.log(f'Sẵn sàng {len(accepted):,}/{db.rows:,} mục; {len(issues):,} mục cần kiểm tra. Báo cáo: data/reports.')
        return ar, db, accepted, report

    def build_slots(self, descriptor, payloads_dir):
        self.log('Phát hiện gói 29 slots; đang nạp toàn bộ cốt truyện và giao diện...')
        ar, _ = self.original_archive()
        build = self.data / 'builds' / ('slots-' + uuid.uuid4().hex[:12])
        chunks_out = build / 'chunks'
        chunks_out.mkdir(parents=True, exist_ok=True)

        manifest_data = bytearray(ar.data)
        chunk_buffers = {}
        applied_count = 0
        patches = descriptor.get('patches', [])

        for p in patches:
            fname = p['file']
            chunk_name = p.get('chunk')
            is_optional = p.get('optional', False)

            if fname not in ar.files:
                if is_optional:
                    continue
                raise FormatError(f'Tệp kịch bản không tồn tại trong manifest: {fname}')

            f = ar.files[fname]
            segs = ar.segments(f)
            if not segs:
                if is_optional:
                    continue
                raise FormatError(f'Không tìm thấy segment cho: {fname}')

            c, off, size = segs[0]
            rel_chunk = f'chunks/{c["name"]}'
            live_chunk_file = self.resources / rel_chunk
            if not live_chunk_file.is_file():
                if fname != 'text/ja/text.db' or is_optional:
                    continue
                raise FileNotFoundError(f'Thiếu chunk bắt buộc trong game: {rel_chunk}')

            pl_name = Path(p['payload']).name
            pl_file = payloads_dir / pl_name
            if not pl_file.is_file():
                if is_optional:
                    continue
                raise FileNotFoundError(f'Thiếu payload: {pl_name}. Vui lòng bấm nút "Cập nhật tiếng Việt" trên launcher để tải lại gói dữ liệu.')

            pl_bytes = pl_file.read_bytes()
            if len(pl_bytes) > size:
                raise FormatError(f'Payload {pl_name} vượt kích thước slot {size}')

            if c['name'] not in chunk_buffers:
                chunk_buffers[c['name']] = bytearray(live_chunk_file.read_bytes())

            buf = chunk_buffers[c['name']]
            buf[off : off + len(pl_bytes)] = pl_bytes
            buf[off + len(pl_bytes) : off + size] = b'\x00' * (size - len(pl_bytes))

            struct.pack_into('<II', manifest_data, f['entry'] + 16, len(pl_bytes), p['target_us'])
            manifest_data[f['entry'] + 32] = 1
            struct.pack_into('<Q', manifest_data, ar.fhash + f['index'] * 8, int(p['target_xxh64'], 16))
            applied_count += 1

        for cname, buf in chunk_buffers.items():
            chunk_info = next(c for c in ar.chunks if c['name'] == cname)
            checksum = xxhash.xxh64_intdigest(memoryview(buf)[:-16])
            struct.pack_into('<Q', buf, len(buf) - 8, checksum)
            struct.pack_into('<Q', manifest_data, ar.chunk_table + chunk_info['index'] * 32 + 24, checksum)
            (chunks_out / cname).write_bytes(buf)

        (build / 'manifest.ssra').write_bytes(manifest_data)

        for rel in IDENTITY_FILES:
            source = self.resources / rel
            if not source.exists():
                continue
            if rel.endswith('.etag'):
                original = manifest_identity(source.read_bytes(), ar.data)
                patched = manifest_identity(source.read_bytes(), bytes(manifest_data))
            else:
                original, patched = ar.data, bytes(manifest_data)
            atomic_bytes(build / 'original_metadata' / rel, original)
            atomic_bytes(build / rel, patched)

        report = {
            'schema': 1,
            'slots_mode': True,
            'applied_slots': applied_count,
            'total_slots': len(patches),
            'touched_chunks': sorted(chunk_buffers.keys()),
            'translated': applied_count,
            'manifest_sha256': hashlib.sha256(manifest_data).hexdigest(),
            'identity_synced': (build / IDENTITY_FILES[0]).exists()
        }
        write_json(build / 'build.json', report)
        self.log(f'Đã nạp thành công {applied_count}/{len(patches)} slots dữ liệu game.')
        return ar, build, report

    def build(self):
        desc_file = self.data / 'release.descriptor.json'
        payloads_dir = self.data / 'payload'
        if desc_file.is_file() and payloads_dir.is_dir():
            return self.build_slots(read_json(desc_file), payloads_dir)
        ar, db, accepted, report = self.sync()
        if not accepted:
            raise ValueError('Chưa có bản dịch hợp lệ để cài.')
        build = self.data / 'builds' / (report['manifest_sha256'][:16] + '-' + uuid.uuid4().hex[:8])
        self.log('Đang dựng gói ngôn ngữ và kiểm tra đọc lại...')
        stats = ar.patch_text(accepted, build)
        from story_localization import (
            build_story, STORY_FILE,
            build_sub_story, SUB_STORY_FILE,
            build_messenger_story, MESSENGER_STORY_FILE,
            build_visit_story, VISIT_STORY_FILE,
            build_friendship_story, FRIENDSHIP_STORY_FILE,
            build_counseling_story, COUNSELING_STORY_FILE
        )
        story_payload, story_report = build_story(ar, self.home)
        report['story'] = story_report
        if story_payload is not None:
            overrides = {p.name: p for p in (build / 'chunks').glob('*.ssrc')}
            combined = Archive(ar.root, build / 'manifest.ssra', ar.overrides | overrides)
            story_report['archive_patch'] = combined.patch_story_file(STORY_FILE, story_payload, build)
            stats['chunks'] = sorted({*stats['chunks'], *story_report['archive_patch']['chunks']})
            self.log(f'Cốt truyện chính: {story_report["translated"]}/{story_report["total"]} mục; chỉ đổi trường text_ja.')

        sub_story_payload, sub_story_report = build_sub_story(ar, self.home)
        report['sub_story'] = sub_story_report
        if sub_story_payload is not None:
            overrides = {p.name: p for p in (build / 'chunks').glob('*.ssrc')}
            combined = Archive(ar.root, build / 'manifest.ssra', ar.overrides | overrides)
            sub_story_report['archive_patch'] = combined.patch_story_file(SUB_STORY_FILE, sub_story_payload, build)
            stats['chunks'] = sorted({*stats['chunks'], *sub_story_report['archive_patch']['chunks']})
            self.log(f'Cốt truyện phụ: {sub_story_report["translated"]}/{sub_story_report["total"]} mục; chỉ đổi trường text_ja.')

        messenger_payload, messenger_report = build_messenger_story(ar, self.home)
        report['messenger_story'] = messenger_report
        if messenger_payload is not None:
            overrides = {p.name: p for p in (build / 'chunks').glob('*.ssrc')}
            combined = Archive(ar.root, build / 'manifest.ssra', ar.overrides | overrides)
            messenger_file = messenger_report.get('file', MESSENGER_STORY_FILE)
            messenger_report['archive_patch'] = combined.patch_story_file(messenger_file, messenger_payload, build)
            stats['chunks'] = sorted({*stats['chunks'], *messenger_report['archive_patch']['chunks']})
            self.log(f'Tin nhắn Messenger: {messenger_report["translated"]}/{messenger_report["total"]} mục; chỉ đổi trường text_ja.')

        visit_payload, visit_report = build_visit_story(ar, self.home)
        report['visit_story'] = visit_report
        if visit_payload is not None:
            overrides = {p.name: p for p in (build / 'chunks').glob('*.ssrc')}
            combined = Archive(ar.root, build / 'manifest.ssra', ar.overrides | overrides)
            visit_file = visit_report.get('file', VISIT_STORY_FILE)
            visit_report['archive_patch'] = combined.patch_story_file(visit_file, visit_payload, build)
            stats['chunks'] = sorted({*stats['chunks'], *visit_report['archive_patch']['chunks']})
            self.log(f'Thăm thị trấn: {visit_report["translated"]}/{visit_report["total"]} mục; chỉ đổi trường text_ja.')

        friendship_payload, friendship_report = build_friendship_story(ar, self.home)
        report['friendship_story'] = friendship_report
        if friendship_payload is not None:
            overrides = {p.name: p for p in (build / 'chunks').glob('*.ssrc')}
            combined = Archive(ar.root, build / 'manifest.ssra', ar.overrides | overrides)
            friendship_file = friendship_report.get('file', FRIENDSHIP_STORY_FILE)
            friendship_report['archive_patch'] = combined.patch_story_file(friendship_file, friendship_payload, build)
            stats['chunks'] = sorted({*stats['chunks'], *friendship_report['archive_patch']['chunks']})
            self.log(f'Giao lưu & Tình bạn: {friendship_report["translated"]}/{friendship_report["total"]} mục; chỉ đổi trường text_ja.')

        counseling_payload, counseling_report = build_counseling_story(ar, self.home)
        report['counseling_story'] = counseling_report
        if counseling_payload is not None:
            overrides = {p.name: p for p in (build / 'chunks').glob('*.ssrc')}
            combined = Archive(ar.root, build / 'manifest.ssra', ar.overrides | overrides)
            counseling_file = counseling_report.get('file', COUNSELING_STORY_FILE)
            counseling_report['archive_patch'] = combined.patch_story_file(counseling_file, counseling_payload, build)
            stats['chunks'] = sorted({*stats['chunks'], *counseling_report['archive_patch']['chunks']})
            self.log(f'Tư vấn tâm lý: {counseling_report["translated"]}/{counseling_report["total"]} mục; chỉ đổi trường text_ja.')
        for rel in IDENTITY_FILES:
            source = self.resources / rel
            if not source.exists():
                continue
            if rel.endswith('.etag'):
                original = manifest_identity(source.read_bytes(), ar.data)
                patched = manifest_identity(source.read_bytes(), (build / 'manifest.ssra').read_bytes())
            else:
                original, patched = ar.data, (build / 'manifest.ssra').read_bytes()
            atomic_bytes(build / 'original_metadata' / rel, original)
            atomic_bytes(build / rel, patched)
        stats['identity_synced'] = (build / IDENTITY_FILES[0]).exists()
        report.update(stats)
        write_json(build / 'build.json', report)
        self.log('Bản vá đã vượt qua kiểm tra checksum, giải nén, ID và nội dung.')
        return ar, build, report

    def _retired_chunk_restores(self, ar, files):
        """Restore old managed chunks omitted by a corrected physical mapping.

        In 2.1.16, CNAM could map logical ID 32 to physical base_b31 while
        the installer wrote base_b32. Reinstall must restore that displaced
        file as well as write the newly built canonical chunk, in one journal.
        """
        if not self.state.get('installed'):
            return {}
        retired = [rel for rel in self.state.get('patched_hashes', {})
                   if rel.startswith('chunks/') and rel not in files]
        if not retired:
            return {}

        live_manifest_sha = sha(self.resources / 'manifest.ssra')
        manifest_clean_sha = hashlib.sha256(ar.data).hexdigest()
        manifest_original_sha = self.state.get('original_hashes', {}).get('manifest.ssra')
        manifest_patched_sha = self.state.get('patched_hashes', {}).get('manifest.ssra')

        publisher_updated = (manifest_clean_sha != manifest_original_sha)
        if not publisher_updated:
            # Live manifest must either match the previous patched manifest OR the clean original manifest
            if live_manifest_sha != manifest_patched_sha and live_manifest_sha != manifest_original_sha:
                raise RuntimeError('Game đã thay đổi ngoài dự kiến; hãy kiểm tra tệp bằng STOVE.')

        backup = self._backup_dir()
        chunks = {c['name']: c for c in ar.chunks}
        restored = {}
        for rel in retired:
            if not allowed_resource(rel):
                raise ValueError('Chunk cũ nằm ngoài phạm vi khôi phục.')
            source = contained(backup, rel)
            target = contained(self.resources, rel)
            orig_hash = self.state.get('original_hashes', {}).get(rel)
            patched_hash = self.state.get('patched_hashes', {}).get(rel)

            if not source.is_file() or not target.is_file() or sha(source) != orig_hash:
                raise RuntimeError('Chunk cũ hoặc bản sao lưu đã thay đổi; chưa ghi dữ liệu game: ' + rel)

            target_sha = sha(target)
            if target_sha == orig_hash or target_sha != patched_hash:
                # File is already clean on disk or updated by publisher. No restore needed!
                continue
            elif target_sha == patched_hash:
                if publisher_updated:
                    if source.is_file() and sha(source) == orig_hash:
                        restored[rel] = source
                    else:
                        raise RuntimeError(f'Game đã đổi phiên bản nhưng {Path(rel).name} vẫn mang dữ liệu bản vá cũ. Hãy kiểm tra tệp bằng STOVE.')
                else:
                    name = Path(rel).name
                    if name not in chunks:
                        raise FormatError('Không xác định được tên chunk gốc để khôi phục: ' + name)
                    if not source.is_file() or sha(source) != orig_hash:
                        raise RuntimeError('Bản sao lưu chunk cũ không khớp dữ liệu gốc: ' + rel)
                    check = Archive(ar.root, ar.manifest_path, {name: source})
                    check.chunk_bytes(chunks[name])
                    restored[rel] = source
        return restored

    def _transaction(self, files, new_state, expected_previous=None, expected_sources=None):
        require_game_closed()
        check_write_access(contained(self.resources, rel) for rel in files if allowed_resource(rel))
        txn = self.data / 'transactions' / uuid.uuid4().hex
        previous, upcoming = {}, {}
        for rel, source in files.items():
            if not allowed_resource(rel):
                raise ValueError('Bộ cài chỉ được ghi gói chữ Nhật, vùng chứa kịch bản đã xác minh và metadata.')
            target = contained(self.resources, rel)
            old = contained(txn, rel)
            old.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(target, old)
            previous[rel], upcoming[rel] = sha(old), sha(source)
            if expected_previous is not None and previous[rel] != expected_previous.get(rel):
                raise RuntimeError('Dữ liệu game đã đổi trước giao dịch; chưa ghi bản vá.')
            if expected_sources is not None and upcoming[rel] != expected_sources.get(rel):
                raise RuntimeError('Gói cài hoặc bản sao lưu đã đổi trước giao dịch; chưa ghi bản vá.')
        journal = {'game_dir': str(self.game), 'transaction': str(txn.relative_to(self.data)),
                   'previous_state': self.state, 'previous_hashes': previous, 'next_hashes': upcoming}
        write_json(self.journal_file, journal)
        try:
            for rel, source in files.items():
                target = contained(self.resources, rel)
                if sha(target) != previous[rel]:
                    raise RuntimeError('Game thay đổi trong lúc cài; hãy chờ STOVE cập nhật xong.')
                if sha(source) != upcoming[rel]:
                    raise RuntimeError('Nguồn giao dịch đã thay đổi; chưa ghi tệp này.')
                atomic_bytes(target, Path(source).read_bytes())
                if sha(target) != upcoming[rel]:
                    raise RuntimeError('Kiểm tra file sau ghi thất bại.')
            write_json(self.state_file, new_state)
            self.journal_file.unlink()
            self.state = new_state
        except BaseException:
            self.log('Thao tác lỗi. Đang hoàn nguyên các file đã thay đổi...')
            self.recover()
            raise

    def install(self):
        require_game_closed()
        ar, build, report = self.build()
        files = {'chunks/' + x.name: x for x in (build / 'chunks').glob('*.ssrc')}
        # Write language chunks before the manifest. Interrupted installs are journaled.
        files['manifest.ssra'] = build / 'manifest.ssra'
        files.update({rel: build / rel for rel in IDENTITY_FILES if (build / rel).exists()})
        retired = self._retired_chunk_restores(ar, files)
        files.update(retired)
        report['restored_previous_chunks'] = sorted(retired)
        fingerprint = hashlib.sha256(ar.data).hexdigest()
        backup = self.data / 'backups' / fingerprint
        originals = {}
        for rel in files:
            if rel == 'manifest.ssra':
                source = ar.manifest_path
            elif rel in IDENTITY_FILES:
                source = build / 'original_metadata' / rel
            else:
                source = Path(ar.overrides.get(Path(rel).name, self.resources / rel))
            destination = contained(backup, rel)
            digest = sha(source)
            if destination.exists():
                if sha(destination) != digest:
                    raise RuntimeError('Bản sao lưu phiên bản này khác dữ liệu gốc đang đọc; dừng để bảo vệ bản gốc.')
            else:
                atomic_bytes(destination, source.read_bytes())
            originals[rel] = digest
        # Revalidate the live state after the potentially slow build.
        check_ar, _ = self.original_archive()
        if hashlib.sha256(check_ar.data).hexdigest() != fingerprint:
            raise RuntimeError('Game vừa cập nhật trong lúc dựng gói. Bấm đồng bộ lại sau khi cập nhật hoàn tất.')
        for chunk, _, _ in ar.segments(ar.files['text/ja/text.db']):
            check_ar.chunk_bytes(next(c for c in check_ar.chunks if c['name'] == chunk['name']))
        expected_sources = {rel: sha(p) for rel, p in files.items()}
        state = {'schema': 1, 'installed': True, 'game_dir': str(self.game),
                 'backup': str(backup.relative_to(self.data)),
                 'original_hashes': {rel: d for rel, d in originals.items() if rel not in retired},
                 'patched_hashes': {rel: h for rel, h in expected_sources.items() if rel not in retired},
                 'report': report}
        expected_previous = {rel: sha(contained(self.resources, rel)) for rel in files}
        # Recheck provenance after the build/backup work, immediately before
        # preparing the transaction. Journal previous bytes always come from
        # the live files, including a displaced legacy chunk.
        if self._retired_chunk_restores(ar, {rel: p for rel, p in files.items() if rel not in retired}) != retired:
            raise RuntimeError('Danh sách chunk cần khôi phục đã thay đổi.')
        self._transaction(files, state, expected_previous, expected_sources)
        # Check the installed archive independently, using only the game's current files.
        installed = Archive(self.resources)
        native = Database(installed.read_file('text/ja/text.db'), require_native_phase=True)
        if not report.get('slots_mode') and native.rows != report['rows']:
            raise RuntimeError('Số dòng sau cài không khớp.')
        for chunk in installed.chunks:
            if 'chunks/' + chunk['name'] in files:
                installed.chunk_bytes(chunk)
        if not report.get('slots_mode') and report.get('story', {}).get('translated'):
            from story_format import StoryTable
            from story_localization import STORY_FILE, source_rows
            live_story = source_rows(StoryTable(installed.read_file(STORY_FILE)))
            entries = read_json(self.data / 'story_translations.json')['entries']
            applied_ids = set(report['story']['accepted_ids'])
            count = sum(r['id'] in applied_ids and live_story.get(r['id'], {}).get('source_ja') == r['text_vi'] for r in entries)
            if count != report['story']['translated']:
                raise RuntimeError('Story readback sau cài không khớp.')
            report['story']['installed_readback_match'] = count
        if report.get('sub_story', {}).get('translated'):
            from story_format import StoryTable
            from story_localization import SUB_STORY_FILE, source_rows, SUB_CHAPTER_PREFIXES
            live_sub = source_rows(StoryTable(installed.read_file(SUB_STORY_FILE)), SUB_CHAPTER_PREFIXES)
            entries = read_json(self.data / 'story_sub_translations.json')['entries']
            applied_ids = set(report['sub_story']['accepted_ids'])
            count = sum(r['id'] in applied_ids and live_sub.get(r['id'], {}).get('source_ja') == r['text_vi'] for r in entries)
            if count != report['sub_story']['translated']:
                raise RuntimeError('Sub Story readback sau cài không khớp.')
            report['sub_story']['installed_readback_match'] = count
        self.log(f'Đã cài {report["translated"]:,} mục tiếng Việt. Chọn ngôn ngữ văn bản 日本語 trong game.')
        if report.get('identity_synced'):
            self.log('Đã đồng bộ dấu nhận diện manifest với bản vá; giữ nguyên URL và ETag của phiên bản trên máy chủ.')
        report['file_status'] = self.status()
        write_json(self.data / 'reports' / 'TRANG_THAI.json', report)
        return report

    def install_patch(self, patch_path):
        require_game_closed()
        patch_file = Path(patch_path).resolve()
        if not patch_file.is_file():
            raise FileNotFoundError(f"Không tìm thấy file cập nhật: {patch_file}")

        self.log(f'Đang mở gói cập nhật từ GitHub: {patch_file.name}...')
        import zipfile
        import zstandard as zstd

        with zipfile.ZipFile(patch_file, 'r') as z:
            dctx = zstd.ZstdDecompressor()
            if 'payload/text.zst' not in z.namelist():
                raise ValueError('Gói cập nhật thiếu payload/text.zst')
            decompressed_text = dctx.decompress(z.read('payload/text.zst'))
            patch_db = Database(decompressed_text)
            self.log(f'Đọc được {patch_db.rows:,} mục văn bản từ gói cập nhật.')

            story_payload = None
            if 'payload/story.zst' in z.namelist():
                story_payload = dctx.decompress(z.read('payload/story.zst'))
                self.log('Đã nạp dữ liệu cốt truyện từ gói cập nhật.')

            sub_story_payload = None
            if 'payload/sub_story.zst' in z.namelist():
                sub_story_payload = dctx.decompress(z.read('payload/sub_story.zst'))
                self.log('Đã nạp dữ liệu cốt truyện phụ từ gói cập nhật.')

        ar, db = self.original_archive()
        accepted = {}
        for k, v in patch_db.texts.items():
            if k in db.texts and v != db.texts[k]:
                accepted[k] = v

        if not accepted:
            raise ValueError('Không tìm thấy nội dung tiếng Việt mới cần áp dụng.')

        self.log(f'Áp dụng {len(accepted):,} mục bản dịch tiếng Việt vào game...')
        fingerprint = hashlib.sha256(ar.data).hexdigest()
        build = self.data / 'builds' / (fingerprint[:16] + '-' + uuid.uuid4().hex[:8])
        stats = ar.patch_text(accepted, build)

        from story_localization import STORY_FILE, SUB_STORY_FILE
        if story_payload is not None:
            overrides = {p.name: p for p in (build / 'chunks').glob('*.ssrc')}
            combined = Archive(ar.root, build / 'manifest.ssra', ar.overrides | overrides)
            stats['story_archive_patch'] = combined.patch_story_file(STORY_FILE, story_payload, build)
            stats['chunks'] = sorted({*stats['chunks'], *stats['story_archive_patch']['chunks']})
            self.log('Đã gắn dữ liệu cốt truyện vào chunk game.')

        if sub_story_payload is not None:
            overrides = {p.name: p for p in (build / 'chunks').glob('*.ssrc')}
            combined = Archive(ar.root, build / 'manifest.ssra', ar.overrides | overrides)
            stats['sub_story_archive_patch'] = combined.patch_story_file(SUB_STORY_FILE, sub_story_payload, build)
            stats['chunks'] = sorted({*stats['chunks'], *stats['sub_story_archive_patch']['chunks']})
            self.log('Đã gắn dữ liệu cốt truyện phụ vào chunk game.')

        for rel in IDENTITY_FILES:
            source = self.resources / rel
            if not source.exists():
                continue
            if rel.endswith('.etag'):
                original = manifest_identity(source.read_bytes(), ar.data)
                patched = manifest_identity(source.read_bytes(), (build / 'manifest.ssra').read_bytes())
            else:
                original, patched = ar.data, (build / 'manifest.ssra').read_bytes()
            atomic_bytes(build / 'original_metadata' / rel, original)
            atomic_bytes(build / rel, patched)

        files = {'chunks/' + x.name: x for x in (build / 'chunks').glob('*.ssrc')}
        files['manifest.ssra'] = build / 'manifest.ssra'
        files.update({rel: build / rel for rel in IDENTITY_FILES if (build / rel).exists()})
        backup = self.data / 'backups' / fingerprint
        originals = {}
        for rel in files:
            if rel == 'manifest.ssra':
                source = ar.manifest_path
            elif rel in IDENTITY_FILES:
                source = build / 'original_metadata' / rel
            else:
                source = Path(ar.overrides.get(Path(rel).name, self.resources / rel))
            destination = contained(backup, rel)
            digest = sha(source)
            if destination.exists():
                if sha(destination) != digest:
                    raise RuntimeError('Bản sao lưu trước đó không khớp checksum.')
            else:
                destination.parent.mkdir(parents=True, exist_ok=True)
                atomic_bytes(destination, source.read_bytes())
            originals[rel] = digest

        new_state = {
            'schema': 1,
            'version': VERSION,
            'game_dir': str(self.game),
            'installed': True,
            'backup': str(backup.relative_to(self.data)),
            'original_hashes': originals,
            'patched_hashes': {rel: sha(p) for rel, p in files.items()},
            'patch_file': patch_file.name,
            'time': time.strftime('%Y-%m-%d %H:%M:%S'),
        }
        self.log('Đang ghi bản vá vào game với bảo vệ atomic...')
        self._transaction(files, new_state)
        self.log(f'Đã cài thành công {len(accepted):,} mục tiếng Việt từ gói GitHub!')

    def restore(self):
        require_game_closed()
        self.recover()
        if not self.state.get('installed'):
            raise ValueError('Chưa có bản Việt hóa được bộ cài này quản lý để khôi phục.')
        backup = self._backup_dir()
        live_hash = sha(self.resources / 'manifest.ssra')
        files = {}
        if live_hash == self.state['patched_hashes']['manifest.ssra']:
            for rel, digest in self.state['patched_hashes'].items():
                if rel in IDENTITY_FILES:
                    continue
                if rel not in IDENTITY_FILES and sha(contained(self.resources, rel)) != digest:
                    raise RuntimeError('File đã thay đổi; không khôi phục bản cũ lên game mới. Hãy kiểm tra file bằng STOVE.')
                original = contained(backup, rel)
                if sha(original) != self.state['original_hashes'][rel]:
                    raise RuntimeError('Checksum bản sao lưu không khớp.')
                files[rel] = original
        else:
            # Restore only retained patch chunks that match the updated original manifest.
            ar = Archive(self.resources)
            for c in ar.chunks:
                rel = 'chunks/' + c['name']
                if rel in self.state['patched_hashes'] and sha(contained(self.resources, rel)) == self.state['patched_hashes'][rel]:
                    original = contained(backup, rel)
                    if sha(original) != self.state['original_hashes'][rel]:
                        raise RuntimeError('Checksum bản sao lưu không khớp.')
                    ar.overrides[c['name']] = original
                    ar.chunk_bytes(c)
                    files[rel] = original
            ar.read_file('text/ja/text.db')
        restored_manifest = files.get('manifest.ssra', self.resources / 'manifest.ssra').read_bytes()
        metadata_dir = self.data / 'restore_metadata' / uuid.uuid4().hex
        for rel in IDENTITY_FILES:
            live = self.resources / rel
            if not live.exists():
                continue
            restored = manifest_identity(live.read_bytes(), restored_manifest) if rel.endswith('.etag') else restored_manifest
            if live.read_bytes() != restored:
                destination = metadata_dir / rel
                atomic_bytes(destination, restored)
                files[rel] = destination
        state = dict(self.state, installed=False)
        if files:
            self._transaction(files, state)
        else:
            write_json(self.state_file, state)
            self.state = state
        Archive(self.resources).read_file('text/ja/text.db')
        self.log('Đã khôi phục dữ liệu Nhật gốc, kiểm tra checksum thành công.')

    def import_translations(self, filename):
        ar, db = self.original_archive()
        p = Path(filename)
        if p.suffix.lower() == '.csv':
            with p.open(encoding='utf-8-sig', newline='') as f:
                imported = list(csv.DictReader(f))
        elif p.suffix.lower() == '.json':
            imported = read_json(p)
            if isinstance(imported, dict):
                imported = imported.get('entries')
        else:
            raise ValueError('Chọn file bản dịch JSON hoặc CSV.')
        if not isinstance(imported, list):
            raise ValueError('File không chứa danh sách bản dịch.')
        if imported and any(r.get('file', '').startswith('db/story_') for r in imported):
            from story_localization import import_story
            return import_story(ar, self.home, imported)
        catalog_before = self.catalog_file.read_bytes()
        catalog = self.catalog()
        by_id = {x['id']: x for x in catalog['entries']}
        accepted, rejected, seen = {}, [], set()
        for r in imported:
            key = r.get('id', r.get('ID', ''))
            target = r.get('text_vi', r.get('Tiếng Việt', ''))
            source = r.get('source_ja', r.get('text_ja', r.get('Tiếng Nhật (Gốc)')))
            if not isinstance(target, str) or not target.strip():
                continue
            why = ''
            if key in seen:
                why = 'ID trùng trong file nhập'
            elif key not in db.texts:
                why = 'ID không thuộc game hiện tại'
            elif source != db.texts[key]:
                why = 'Nguồn Nhật không khớp game hiện tại'
            else:
                why = validate_translation(source, target) or ''
            seen.add(key)
            if why:
                rejected.append({'id': key, 'reason': why})
            else:
                prior = by_id.get(key, {})
                accepted[key] = {'id': key, 'source_ja': source, 'text_vi': target,
                                 'text_en': r.get('text_en', r.get('Tiếng Anh (Đối chiếu)', prior.get('text_en', ''))),
                                 'category': r.get('category', r.get('Phân loại', prior.get('category', ''))),
                                 'origin': 'import'}
        # Reject duplicate IDs even when a previous occurrence was valid.
        for r in rejected:
            if r['reason'] == 'ID trùng trong file nhập':
                accepted.pop(r['id'], None)
        if accepted:
            if self.catalog_file.read_bytes() != catalog_before:
                raise RuntimeError('Catalog đã đổi trong lúc kiểm tra bản nhập. Nhập lại từ catalog mới.')
            backup = self.data / 'catalog_backups' / (time.strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:6] + '.json')
            atomic_bytes(backup, self.catalog_file.read_bytes())
            by_id.update(accepted)
            catalog['entries'] = list(by_id.values())
            catalog['revision'] = time.strftime('%Y%m%d-%H%M%S')
            write_json(self.catalog_file, catalog)
        write_json(self.data / 'reports' / 'KET_QUA_NHAP.json', {'accepted': len(accepted), 'rejected': rejected})
        self.log(f'Đã nhập {len(accepted):,} bản dịch; từ chối {len(rejected):,} dòng lỗi. Bấm Cài Việt hóa để áp dụng.')
        return {'accepted': len(accepted), 'rejected': len(rejected)}
