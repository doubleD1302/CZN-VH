"""Inline story JP-only localization, source matching and update review queue."""
from collections import Counter
import json
from pathlib import Path
import re
import time
from czn_format import FormatError, validate_translation
from installer_core import read_json, write_json
from story_format import StoryTable
from translation_quality import HASH_VARS, FORMULAS, tag_balance

STORY_FILE = 'db/story_main_part1new_260729@story.db'
CHAPTER_PREFIX = 'main_part1new_ch01'
CHAPTER_PREFIXES = (CHAPTER_PREFIX, 'main_part1new_ch02', 'main_part1new_ch03', 'main_part1new_ch04', 'main_part1new_ch05', 'main_part1new_tuto')


def source_rows(table, chapter_prefixes=CHAPTER_PREFIXES):
    result = {}
    for scene in table.order:
        if not scene.startswith(chapter_prefixes):
            continue
        for index, line in enumerate(table.scene(scene)):
            if line.get('text_ja'):
                key = line['yuna_key']
                if key in result:
                    raise FormatError('Duplicate story yuna_key')
                result[key] = dict(scene=scene, position=index, source_ja=line['text_ja'],
                                   text_en=line.get('text_en', ''), talker=line.get('talker', ''), field='text_ja')
    return result


def chapter_stats(source, rows):
    def ch_key(scene):
        if scene.startswith('main_part1new_ch'):
            return str(int(scene[len('main_part1new_ch'):len('main_part1new_ch')+2]))
        if 'tuto' in scene:
            return 'tuto'
        return 'other'
    totals = Counter(ch_key(r['scene']) for r in source.values())
    applied = Counter(ch_key(r['scene']) for r in rows)
    return {k: dict(total=totals[k], translated=applied[k], remaining=totals[k] - applied[k])
            for k in sorted(totals.keys())}


def render(table, rows, chapter_prefixes=CHAPTER_PREFIXES):
    """Strictly change only text_ja for the explicit Part 1 whitelist."""
    source, changes, seen = source_rows(table, chapter_prefixes), {}, set()
    for row in rows:
        key = row['id']
        if key in seen:
            raise FormatError('Duplicate story proposal ID: ' + key)
        seen.add(key)
        original = source.get(key)
        if (not original or row.get('file') != STORY_FILE or row.get('field') != 'text_ja' or
                row.get('source_ja') != original['source_ja'] or row.get('scene') != original['scene'] or
                row.get('position') != original['position'] or row.get('talker') != original['talker']):
            raise FormatError('Story ID/source/field mismatch: ' + key)
        target = row['text_vi']
        if not isinstance(target, str) or not target.strip():
            raise FormatError('Empty story translation: ' + key)
        if (re.findall(r'\r\n|\r|\n', original['source_ja']) != re.findall(r'\r\n|\r|\n', target) or
                original['source_ja'].count('|') != target.count('|')):
            raise FormatError('Story newline/choice separator mismatch: ' + key)
        error = validate_translation(original['source_ja'], target)
        if error or Counter(HASH_VARS.findall(original['source_ja'])) != Counter(HASH_VARS.findall(target)):
            raise FormatError('Story token mismatch: ' + key + ': ' + str(error))
        if Counter(FORMULAS.findall(original['source_ja'])) != Counter(FORMULAS.findall(target)):
            raise FormatError('Story formula mismatch')
        if tag_balance(original['source_ja']) and not tag_balance(target):
            raise FormatError('Story tag imbalance')
        scene = original['scene']
        if scene not in changes:
            changes[scene] = table.scene(scene)
        changes[scene][original['position']]['text_ja'] = target
    values = {}
    info_index = table.columns.index('info')
    for scene, lines in changes.items():
        original_lines = table.scene(scene)
        if len(lines) != len(original_lines):
            raise FormatError('Story command count changed')
        for old, new in zip(original_lines, lines):
            if {k:v for k,v in old.items() if k != 'text_ja'} != {k:v for k,v in new.items() if k != 'text_ja'}:
                raise FormatError('Non-JP story field changed')
        value = list(table.values[scene])
        value[info_index] = json.dumps(lines, ensure_ascii=False, separators=(',', ':'))
        values[scene] = value
    encrypted = table.rebuild(values)
    check = StoryTable(encrypted)
    for scene in table.order:
        if check.scene(scene) != changes.get(scene, table.scene(scene)):
            raise FormatError('Story semantic readback mismatch: ' + scene)
    return encrypted, dict(translated=len(rows), total=len(source), remaining=len(source) - len(rows),
                           scenes=len(changes), native_phase=check.phase, db_size=len(encrypted),
                           only_text_ja_changed=True, other_languages_identical=True,
                           scene_commands_identical=True, outside_chapter_identical=True,
                           chapters=chapter_stats(source, rows))


def build_story(archive, home):
    catalog_path = Path(home) / 'data/story_translations.json'
    if not catalog_path.exists():
        return None, dict(enabled=False, translated=0)
    catalog = read_json(catalog_path)
    if catalog.get('schema') != 1 or not isinstance(catalog.get('entries'), list):
        raise FormatError('Invalid story catalog')
    if STORY_FILE not in archive.files:
        write_json(Path(home) / 'data/reports/STORY_CAN_DICH_MOI.json',
                   dict(file=STORY_FILE, requires_extraction=True, entries=[], stale_entries=catalog['entries']))
        return None, dict(enabled=True, translated=0, requires_update=True,
                          message='Game đã đổi file cốt truyện; cần trích lại nguồn, không mang bản dịch cũ sang.')
    table = StoryTable(archive.read_file(STORY_FILE))
    source = source_rows(table)
    accepted, issues, seen = [], [], set()
    for row in catalog['entries']:
        if row.get('id') in seen:
            raise FormatError('Duplicate story catalog ID')
        seen.add(row.get('id'))
        original = source.get(row.get('id'))
        if (original and row.get('source_ja') == original['source_ja'] and
                row.get('scene') == original['scene'] and row.get('talker') == original['talker']):
            # Stable JP/ID/speaker in the same scene can move when new script
            # commands are inserted. Always address the current source position.
            accepted.append(dict(row, **original, file=STORY_FILE))
        else:
            issues.append(dict(id=row.get('id'), reason='ID/JP/scene/speaker changed after game update', previous_source_ja=row.get('source_ja')))
    accepted_ids = {r['id'] for r in accepted}
    pending = [dict(id=key, **row) for key,row in source.items() if key not in accepted_ids]
    report_folder = Path(home) / 'data/reports'
    write_json(report_folder / 'STORY_CAN_DICH_MOI.json', dict(entries=pending, stale_entries=issues, file=STORY_FILE))
    if not accepted:
        return None, dict(enabled=True, translated=0, total=len(source), remaining=len(source), issues=issues,
                          chapters=chapter_stats(source, []))
    encrypted, report = render(table, accepted)
    report.update(enabled=True, issues=issues, revision=catalog.get('revision'), file=STORY_FILE,
                  accepted_ids=sorted(accepted_ids))
    return encrypted, report


def import_story(archive, home, rows):
    """All-or-nothing story import after exact source and engine-format checks."""
    import hashlib
    import uuid
    home = Path(home)
    table = StoryTable(archive.read_file(STORY_FILE))
    render(table, rows)
    path = home / 'data/story_translations.json'
    previous = path.read_bytes() if path.exists() else None
    old = read_json(path) if previous else dict(schema=1, entries=[])
    by_id = {r['id']: r for r in old['entries']}
    by_id.update({r['id']: r for r in rows})
    if previous:
        from installer_core import atomic_bytes
        atomic_bytes(home / 'data/catalog_backups' / ('story-' + time.strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:6] + '.json'), previous)
    if path.exists() and previous != path.read_bytes():
        raise FormatError('Story catalog changed during import; retry after other editor finishes')
    write_json(path, dict(schema=1, revision=time.strftime('%Y%m%d-%H%M%S'), file=STORY_FILE,
                         source_manifest_sha256=hashlib.sha256(archive.data).hexdigest(), entries=list(by_id.values())))
    return dict(accepted=len(rows), rejected=0, catalog='story', requires_install=True)
