"""Durable translation observations and release receipts; never infer semantic review."""
from __future__ import annotations
import argparse
import hashlib
import json
import re
import sqlite3
import uuid
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

CATALOGS = {'text': 'translations.json', 'story': 'story_translations.json'}

def encoded(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'))

def sha(data):
    return hashlib.sha256(data).hexdigest()

def now():
    return datetime.now(timezone.utc).isoformat()

def connect(home):
    directory = Path(home) / 'data/change_history'
    directory.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(directory / 'history.sqlite3', timeout=30)
    db.execute('PRAGMA journal_mode=WAL')
    db.execute('PRAGMA synchronous=FULL')
    db.executescript('''
        CREATE TABLE IF NOT EXISTS observed(domain TEXT,id TEXT,row TEXT,
            PRIMARY KEY(domain,id));
        CREATE TABLE IF NOT EXISTS events(sequence INTEGER PRIMARY KEY,
            stamp TEXT,domain TEXT,id TEXT,before_row TEXT,after_row TEXT,
            before_sha256 TEXT,after_sha256 TEXT,context TEXT);
        CREATE TABLE IF NOT EXISTS captures(id TEXT PRIMARY KEY,stamp TEXT,
            domain TEXT,catalog_sha256 TEXT,kind TEXT,count INTEGER,context TEXT);
        CREATE TABLE IF NOT EXISTS state(key TEXT PRIMARY KEY,value TEXT);
        CREATE TABLE IF NOT EXISTS published(domain TEXT,id TEXT,value TEXT,
            PRIMARY KEY(domain,id));
        CREATE TABLE IF NOT EXISTS publications(bundle_sha256 TEXT PRIMARY KEY,
            stamp TEXT,version TEXT,receipt TEXT);
    ''')
    return db

def document_rows(document):
    result = {}
    for row in document.get('entries', []):
        identity = row.get('id')
        if not isinstance(identity, str) or identity in result:
            raise ValueError('Catalog có ID thiếu/trùng; chưa ghi lịch sử.')
        result[identity] = row
    return result

def observe_document(home, domain, document, catalog_hash, context=None):
    """First inventory has no invented completion date. Later edits keep before/after."""
    rows = document_rows(document)
    context = context or {'operation': 'catalog_observed', 'semantic_review': 'not_inferred'}
    db = connect(home)
    try:
        with db:
            initialized = db.execute('SELECT value FROM state WHERE key=?', ('seen:' + domain,)).fetchone()
            previous = dict(db.execute('SELECT id,row FROM observed WHERE domain=?', (domain,)))
            changes = []
            for identity in previous.keys() | rows.keys():
                old = previous.get(identity)
                new = encoded(rows[identity]) if identity in rows else None
                if old == new:
                    continue
                if initialized:
                    changes.append((now(), domain, identity, old, new,
                                    sha(old.encode()) if old else None,
                                    sha(new.encode()) if new else None, encoded(context)))
                if new is None:
                    db.execute('DELETE FROM observed WHERE domain=? AND id=?', (domain, identity))
                else:
                    db.execute('INSERT OR REPLACE INTO observed VALUES(?,?,?)', (domain, identity, new))
            db.executemany('INSERT INTO events(stamp,domain,id,before_row,after_row,before_sha256,after_sha256,context) VALUES(?,?,?,?,?,?,?,?)', changes)
            if not initialized or changes or context.get('summary') or context.get('evidence'):
                db.execute('INSERT INTO captures VALUES(?,?,?,?,?,?,?)',
                           (uuid.uuid4().hex, now(), domain, catalog_hash,
                            'changes' if initialized else 'initial_inventory',
                            len(changes) if initialized else len(rows), encoded(context)))
            db.execute('INSERT OR REPLACE INTO state VALUES(?,?)', ('seen:' + domain, catalog_hash))
        return len(changes)
    finally:
        db.close()

def capture(home, summary='', evidence=()):
    proof = []
    for name in evidence:
        path = Path(name).resolve()
        proof.append({'path': str(path), 'sha256': sha(path.read_bytes())})
    context = {'operation': 'agent_capture', 'summary': summary, 'evidence': proof,
               'semantic_review': 'not_inferred'}
    counts = {}
    for domain, name in CATALOGS.items():
        path = Path(home) / 'data' / name
        raw = path.read_bytes() if path.exists() else b'{"entries":[]}'
        counts[domain] = observe_document(home, domain, json.loads(raw.decode('utf-8-sig')), sha(raw), context)
    return counts

def tracked_write(path, raw, writer):
    """Commit the old observation before writing; next scan recovers a post-write crash."""
    path = Path(path)
    domain = next((k for k, v in CATALOGS.items() if path.name == v and path.parent.name == 'data'), None)
    if not domain:
        writer(path, raw)
        return
    # A malformed proposal must fail before replacing the catalog.
    document_rows(json.loads(raw.decode('utf-8-sig')))
    home = path.parent.parent
    existed = path.exists()
    before = path.read_bytes() if existed else b'{"entries":[]}'
    context = {'operation': 'catalog_write', 'semantic_review': 'not_inferred'}
    observe_document(home, domain, json.loads(before.decode('utf-8-sig')), sha(before), context)
    # Refuse overwriting an edit made while the initial observation was committed.
    if path.exists() != existed or (existed and path.read_bytes() != before):
        raise RuntimeError('Catalog đã đổi trong lúc ghi lịch sử; nhập lại từ bản mới.')
    writer(path, raw)
    # Read the actual file rather than attributing a subsequent writer's bytes to this write.
    actual = path.read_bytes()
    observe_document(home, domain, json.loads(actual.decode('utf-8-sig')), sha(actual), context)

def snapshot_from_tables(text, story, original_text=None, original_story=None):
    from story_localization import source_rows
    story_rows = source_rows(story)
    values = {'text': dict(text.texts), 'story': {k: v['source_ja'] for k, v in story_rows.items()}}
    eligible = {'text': [], 'story': []}
    if original_text is not None:
        eligible['text'] = [k for k, v in text.texts.items() if original_text.texts[k] != v]
    if original_story is not None:
        old = source_rows(original_story)
        eligible['story'] = [k for k, v in values['story'].items() if old[k]['source_ja'] != v]
    return {'schema': 1, 'values': values, 'eligible': eligible}

def read_bundle_snapshot(bundle, channel):
    import zipfile
    from android_sync import verify_metadata
    from czn_format import Database, zstd
    from story_format import StoryTable
    from package_android_patch import STORY
    raw = Path(bundle).read_bytes()
    if sha(raw) != channel['patch_sha256'] or len(raw) != channel['patch_size']:
        raise ValueError('Gói nền không khớp hash/kích thước kênh đã ký.')
    with zipfile.ZipFile(bundle) as archive:
        if archive.getinfo('release.json').file_size > 262144:
            raise ValueError('Metadata gói nền quá lớn.')
        descriptor = verify_metadata(archive.read('release.json'))
        if descriptor.get('schema') != 2 or descriptor.get('version_code') != channel['patch_code'] or descriptor.get('version') != channel['patch_version']:
            raise ValueError('Phiên bản gói nền không khớp kênh đã ký.')
        expected = {'text/ja/text.db': 'payload/text.zst', STORY: 'payload/story.zst'}
        patches = descriptor['patches']
        if len(patches) != 2 or {p['file']: p['payload'] for p in patches} != expected:
            raise ValueError('Gói nền chứa slot ngoài phạm vi.')
        tables = {}
        for patch in patches:
            if not 0 < patch['target_us'] <= 256 * 1024 * 1024 or archive.getinfo(patch['payload']).file_size != patch['target_cs']:
                raise ValueError('Kích thước slot nền không hợp lệ.')
            payload = archive.read(patch['payload'])
            if sha(payload) != patch['target_sha256']:
                raise ValueError('Hash slot nền không khớp.')
            decoded = zstd.ZstdDecompressor().decompress(payload, max_output_size=patch['target_us'], allow_extra_data=False)
            if len(decoded) != patch['target_us']:
                raise ValueError('Kích thước native nền không khớp.')
            tables[patch['file']] = decoded
    return snapshot_from_tables(Database(tables['text/ja/text.db'], require_native_phase=True), StoryTable(tables[STORY]))

def acknowledge(home, snapshot, channel, receipt):
    """Caller supplies a verified public receipt; only the frozen bundle becomes baseline."""
    if not receipt.get('public_verified') or receipt.get('bundle_sha256') != channel['patch_sha256']:
        raise ValueError('Chưa xác thực phát hành công khai; giữ các mục chờ.')
    db = connect(home)
    try:
        with db:
            db.execute('DELETE FROM published')
            db.executemany('INSERT INTO published VALUES(?,?,?)',
                           ((domain, identity, value) for domain, rows in snapshot['values'].items() for identity, value in rows.items()))
            db.execute('INSERT OR REPLACE INTO state VALUES(?,?)', ('baseline', encoded(channel)))
            db.execute('INSERT OR IGNORE INTO publications VALUES(?,?,?,?)',
                       (channel['patch_sha256'], now(), channel['patch_version'], encoded(receipt)))
    finally:
        db.close()

def ensure_baseline(home, channel):
    """Use the actual public JP payloads, never assume today's catalogs were uploaded."""
    from android_sync import fetch
    from installer_core import atomic_bytes
    db = connect(home)
    try:
        row = db.execute('SELECT value FROM state WHERE key="baseline"').fetchone()
        if row and json.loads(row[0])['patch_sha256'] == channel['patch_sha256']:
            return
    finally:
        db.close()
    home = Path(home)
    candidates = list((home / 'data/releases').glob('*/CZN_Android_*.cznpatch'))
    candidates += [home / 'czn_android_patcher/android/app/src/main/assets/bundled.cznpatch',
                   home / 'android/app/src/main/assets/bundled.cznpatch']
    bundle = next((p for p in candidates if p.is_file() and p.stat().st_size == channel['patch_size'] and sha(p.read_bytes()) == channel['patch_sha256']), None)
    if bundle is None:
        raw = fetch(channel['patch_url'], limit=64 * 1024 * 1024)
        if len(raw) != channel['patch_size'] or sha(raw) != channel['patch_sha256']:
            raise ValueError('Gói nền tải từ GitHub không khớp kênh đã ký.')
        bundle = home / 'data/change_history' / (channel['patch_sha256'] + '.cznpatch')
        atomic_bytes(bundle, raw)
    snapshot = read_bundle_snapshot(bundle, channel)
    acknowledge(home, snapshot, channel, {'public_verified': True, 'method': 'live_signed_channel_and_verified_native_bundle',
                                         'bundle_sha256': channel['patch_sha256'], 'url': channel['patch_url']})

def changes_since_publication(home, snapshot=None):
    db = connect(home)
    try:
        # Keep baseline, published rows and observed rows from one SQLite snapshot.
        db.execute('BEGIN')
        baseline = db.execute('SELECT value FROM state WHERE key="baseline"').fetchone()
        if not baseline:
            raise RuntimeError('Chưa có gói nền đã xác thực. Bấm Kiểm tra cập nhật để lấy thay đổi chưa phát hành.')
        published = {(d, i): v for d, i, v in db.execute('SELECT domain,id,value FROM published')}
        observed = {(d, i): json.loads(r) for d, i, r in db.execute('SELECT domain,id,row FROM observed')}
        result = []
        for (domain, identity), row in observed.items():
            value = row.get('text_vi', '')
            if not value or value == row.get('source_ja'):
                continue
            if snapshot is not None and (identity not in snapshot['eligible'][domain] or snapshot['values'][domain].get(identity) != value):
                continue
            before = published.get((domain, identity))
            if before == value:
                continue
            result.append({'domain': domain, 'id': identity, 'group': group_name(domain, row),
                           'kind': 'new' if before is None or before == row.get('source_ja') else 'edited',
                           'before': before, 'after': value, 'after_sha256': sha(value.encode()),
                           'source_ja': row.get('source_ja', row.get('text_ja', '')),
                           'reference_en': row.get('reference_en', row.get('text_en', '')),
                           'metadata': {k: row[k] for k in ('scene', 'talker', 'name_override', 'file') if k in row}})
        # Catalog removals/reverts are announced only when the built payload actually reverts that exact VI.
        if snapshot is not None:
            seen = set()
            for domain, identity, before_raw, after_raw in db.execute('SELECT domain,id,before_row,after_row FROM events ORDER BY sequence DESC'):
                key = domain, identity
                if key in seen:
                    continue
                seen.add(key)
                if after_raw is not None or not before_raw:
                    continue
                old = json.loads(before_raw)
                target = snapshot['values'][domain].get(identity)
                if target == old.get('source_ja') and published.get(key) == old.get('text_vi') and target != old.get('text_vi'):
                    result.append({'domain': domain, 'id': identity, 'group': group_name(domain, old),
                                   'kind': 'removed', 'before': old['text_vi'], 'after': target, 'after_sha256': sha(target.encode()),
                                   'source_ja': old.get('source_ja', old.get('text_ja', '')),
                                   'reference_en': old.get('reference_en', old.get('text_en', '')),
                                   'metadata': {k: old[k] for k in ('scene', 'talker', 'name_override', 'file') if k in old}})
            # Also capture regressions for rows still in catalog whose target native value reverted to source_ja
            announced_ids = {(r['domain'], r['id']) for r in result}
            for (domain, identity), before_val in published.items():
                key = domain, identity
                if key in announced_ids:
                    continue
                row = observed.get(key)
                if not row:
                    continue
                source_ja = row.get('source_ja', row.get('text_ja', ''))
                if not before_val or before_val == source_ja:
                    continue
                target = snapshot['values'][domain].get(identity)
                if target == source_ja and target != before_val:
                    result.append({'domain': domain, 'id': identity, 'group': group_name(domain, row),
                                   'kind': 'removed', 'before': before_val, 'after': target, 'after_sha256': sha(target.encode()),
                                   'source_ja': source_ja,
                                   'reference_en': row.get('reference_en', row.get('text_en', '')),
                                   'metadata': {k: row[k] for k in ('scene', 'talker', 'name_override', 'file') if k in row}})
        return {'baseline_version': json.loads(baseline[0])['patch_version'], 'changes': result}
    finally:
        db.close()

def group_name(domain, row):
    if domain == 'text':
        category = row.get('category') or 'Giao diện và cơ chế'
        if 'UI General' in category:
            return 'Giao diện chung'
        if 'Tech & Audio' in category:
            return 'Thiết lập và âm thanh'
        return re.sub(r'\s*\(Phase\s*\d+\)', '', category)
    match = re.search(r'_(ch\d+|tuto)', row.get('scene', row['id']))
    return 'Cốt truyện · ' + (('Chương ' + str(int(match[1][2:]))) if match and match[1].startswith('ch') else ('Hướng dẫn' if match and match[1] == 'tuto' else 'Chưa xác định chương'))

def notice_text(delta, context=None):
    from player_changelog import model
    return model(delta, context)['text']


def notice_preview_data(home, channel):
    from player_changelog import for_home, model
    capture(home)
    ensure_baseline(home, channel)
    delta = changes_since_publication(home)
    context = for_home(home, delta) if delta['changes'] else None
    return model(delta, context)


def notice_preview(home, channel):
    return notice_preview_data(home, channel)['text']


def main():
    parser = argparse.ArgumentParser(description='Lưu dấu vết thay đổi catalog CZN, không ghi game.')
    parser.add_argument('--home', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--summary', default='')
    parser.add_argument('--evidence', type=Path, action='append', default=[])
    args = parser.parse_args()
    counts = capture(args.home, args.summary, args.evidence)
    print(encoded({'captured': counts, 'history': str(args.home / 'data/change_history/history.sqlite3')}))

if __name__ == '__main__':
    main()
