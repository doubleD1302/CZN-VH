"""Source-backed translation registries and a read-only pre-import audit."""
import argparse
from collections import Counter
import csv
from datetime import datetime, timezone, timedelta
import hashlib
import io
import json
from pathlib import Path
import re
import sys
import unicodedata
import uuid

from czn_format import Database, TOKENS, validate_translation
from installer_core import Installer, read_json, write_json, sha, atomic_bytes
from name_policy import REGISTRY_FILE, EN_ONLY_KINDS, build_registry, name_findings

HASH_VARS = re.compile(r'#[A-Za-z_][A-Za-z_0-9]*#')
FORMULAS = re.compile(r'\{cal\}.*?\{/\}', re.S)
TAGS = re.compile(r'<[^>\r\n]*>')
JAPANESE = re.compile(r'[\u3041-\u3096\u30a1-\u30fa\u4e00-\u9fff]')
PROPER_KINDS = {'character_name', 'character_alias'}
EFFECT_KINDS = {'effect_name', 'keyword', 'effect_or_keyword_candidate'}
MECHANICS = ('card@desc@', 'tooltip@desc@', 'encounter_option_eff@eff_description@',
             'savedata_edit_corruption@desc@', 'piece_set_option@desc@', 'stagecs@desc@')


def now():
    return datetime.now(timezone.utc).astimezone(timezone(timedelta(hours=7))).isoformat(timespec='seconds')


def visible(text):
    return HASH_VARS.sub(' ', TOKENS.sub(' ', text))


def tag_balance(text):
    depth = 0
    for tag in TAGS.findall(text):
        if tag.lower() in ('<br>', '<br/>', '<br />') or (not tag.startswith('</') and tag.endswith('/>')):
            continue
        depth += -1 if tag.startswith('</') else 1
        if depth < 0:
            return False
    return depth == 0


def occurrences(name, text):
    # Avoid treating リン as part of a longer Katakana name, or Rin in a word.
    boundary = r'A-Za-z0-9\u30a1-\u30ff'
    return len(re.findall(r'(?<![' + boundary + '])' + re.escape(name) +
                          r'(?![' + boundary + '])', text))


def numbers(text):
    plain = unicodedata.normalize('NFKC', visible(text))
    return Counter(re.findall(r'\d+(?:\.\d+)?', plain))


def mechanic_numbers_match(source, target):
    expected, actual = numbers(source), numbers(target)
    # Count spelled quantities only when they account for a missing JP digit.
    # "Một chiến binh ngẫu nhiên" may express ランダムな戦闘員 with no digit.
    words = {'một': '1', 'hai': '2', 'ba': '3', 'bốn': '4', 'năm': '5',
             'sáu': '6', 'bảy': '7', 'tám': '8', 'chín': '9', 'mười': '10'}
    for word, digit in words.items():
        missing = max(0, expected[digit] - actual[digit])
        spelled = len(re.findall(r'\b' + word + r'\s+(?=(?:thẻ|lượt|lần|điểm|chiến binh|quái vật|trang bị)\b)',
                                 visible(target), flags=re.I))
        actual[digit] += min(missing, spelled)
    return expected == actual


def english_alias(reference):
    # Use the rendered literal name from the same EN ID. A dynamic counter
    # belongs outside the bilingual name; copying it twice changes the tokens.
    plain = HASH_VARS.sub('', TAGS.sub('', reference))
    plain = re.sub(r'\$([^$]+)\$', r'\1', plain)
    plain = re.sub(r'\s+', ' ', plain).strip()
    return plain if plain and not TOKENS.search(plain) else ''


def choose_name_lock(key, source, official_en, catalog, ja, prior):
    current = catalog.get(key, {}).get('text_vi', '')
    same_source = (prior.get('source_ja') == source and
                   prior.get('reference_en') == official_en)
    if same_source and prior.get('review_status') == 'reviewed':
        return prior['locked_name'], 'manual_reviewed', prior.get('catalog_evidence_ids', [])
    if current and current in (source, official_en):
        return current, 'catalog_name_field', [key]
    evidence = []
    if official_en and official_en != source:
        for row in catalog.values():
            row_source = row.get('source_ja', row.get('text_ja', ''))
            if row_source != ja.get(row['id']):
                continue
            count = occurrences(source, visible(row_source))
            if count and occurrences(official_en, visible(row['text_vi'])) >= count:
                evidence.append(row['id'])
                if len(evidence) == 10:
                    break
    if evidence:
        return official_en, 'verified_official_en_in_existing_sentence', evidence
    return source, 'jp_default', []


def inputs(home, game=None):
    if (home / 'data/journal.json').exists():
        raise RuntimeError('Có giao dịch dang dở; xử lý bằng bộ cài trước khi lấy nguồn kiểm chứng.')
    game = game or Path(read_json(home / 'data/settings.json', {}).get('game_dir', home.parent))
    inst = Installer(home, game, log=lambda message: None)
    archive, db = inst.original_archive()
    en = Database(archive.read_file('text/en/text.db'), require_native_phase=True).texts
    return inst, db.texts, en, hashlib.sha256(archive.data).hexdigest()


def old_entries(path):
    return {r['id']: r for r in read_json(path, {'entries': []})['entries']}


def prepare(home, game=None):
    inst, ja, en, fingerprint = inputs(home, game)
    catalog = {r['id']: r for r in inst.catalog()['entries']}
    previous_names = old_entries(home / 'TEN_NHAN_VAT.json')
    previous_effects = old_entries(home / 'TEN_HIEU_UNG.json')
    glossary = read_json(home / 'THUAT_NGU.json', {}).get('terms', {})
    names, effects, canonical = [], [], {}
    # Explicit char_base labels are stronger evidence than guessed actor labels.
    for key, source in ja.items():
        if not key.startswith('char_base@name@') or key.split('@')[-1].startswith('999'):
            continue
        if source in ('獣人', '二人の友だち') or not source or TOKENS.search(source):
            continue
        prior = previous_names.get(key, {})
        lock, basis, evidence_ids = choose_name_lock(key, source, en.get(key, ''), catalog, ja, prior)
        canonical.setdefault(source, lock)
        names.append(dict(id=key, source_ja=source, reference_en=en.get(key, ''),
                          locked_name=lock, kind='character_name',
                          lock_basis=basis, catalog_evidence_ids=evidence_ids,
                          review_status='reviewed' if basis == 'manual_reviewed' else 'source_verified',
                          source_changed=bool(prior and (prior.get('source_ja') != source or
                                                        prior.get('reference_en') != en.get(key, '') or
                                                        (prior.get('source_changed') and prior.get('review_status') != 'reviewed'))),
                          evidence='char_base@name: JP/EN ghép bằng cùng ID trong archive gốc'))
        if basis == 'manual_reviewed' and 'review_note' in prior:
            names[-1]['review_note'] = prior['review_note']
    for key, source in ja.items():
        if not key.startswith('actor@name@'):
            continue
        prior = previous_names.get(key, {})
        known = source in canonical
        record = dict(id=key, source_ja=source, reference_en=en.get(key, ''),
                      locked_name=canonical.get(source, ''),
                      kind='character_alias' if known else 'unclassified_actor_label',
                      source_changed=bool(prior and (prior.get('source_ja') != source or
                                                    prior.get('reference_en') != en.get(key, '') or
                                                    (prior.get('source_changed') and prior.get('review_status') != 'reviewed'))),
                      evidence='actor@name: cùng tên JP với char_base' if known else
                               'actor@name: cần phân biệt tên riêng, vai trò hoặc placeholder')
        if prior and not record['source_changed'] and prior.get('review_status') == 'reviewed':
            record.update({k: prior[k] for k in ('locked_name', 'kind', 'review_note', 'review_status') if k in prior})
        names.append(record)
    for key, source in ja.items():
        if not key.startswith(('tooltip@title@', 'stagecs@name@', 'keyword_list@name@')):
            continue
        prior = previous_effects.get(key, {})
        reference = en.get(key, '')
        english = english_alias(reference)
        known = key.startswith(('tooltip@title@talent_', 'tooltip@title@card_',
                                'tooltip@title@t_cs', 'stagecs@name@', 'keyword_list@name@'))
        kind = 'effect_or_keyword_candidate' if known else 'title_candidate'
        if re.fullmatch(r'\$[^$]+\$', source):
            kind = 'linked_label'
        elif not visible(source).strip():
            kind = 'dynamic_value_label'
        elif key.startswith('tooltip@title@card_target_'):
            kind = 'condition_label'
        current = catalog.get(key, {}).get('text_vi', '')
        candidate = HASH_VARS.sub('', TAGS.sub('', current)).strip() or glossary.get(source, '')
        if english and candidate.endswith(' (' + english + ')'):
            candidate = candidate[:-(len(english) + 3)].strip()
        if JAPANESE.search(visible(candidate)) or candidate == english:
            candidate = ''
        record = dict(id=key, source_ja=source, reference_en=reference,
                      english_name=english, vi_name=candidate, kind=kind,
                      review_status='candidate',
                      source_hash_variables=HASH_VARS.findall(source),
                      english_name_derivation='same EN ID; rendering tags, # variables and $ wrappers removed',
                      source_changed=bool(prior and (prior.get('source_ja') != source or
                                                    prior.get('reference_en') != reference or
                                                    (prior.get('source_changed') and prior.get('review_status') != 'reviewed'))),
                      evidence='text/ja/text.db và text/en/text.db ghép bằng cùng ID')
        if prior and not record['source_changed'] and prior.get('review_status') == 'reviewed':
            record.update({k: prior[k] for k in ('vi_name', 'kind', 'review_status', 'review_note') if k in prior})
        record['display_candidate'] = (record['vi_name'] + ' (' + record['english_name'] + ')'
                                       if record['vi_name'] and record['english_name'] else '')
        effects.append(record)
    common = dict(schema=1, updated_at=now(), source_manifest_sha256=fingerprint,
                  source_priority='ja', english_source='text/en/text.db; exact same ID')
    write_json(home / 'TEN_NHAN_VAT.json', common | {'entries': names})
    write_json(home / 'TEN_HIEU_UNG.json', common | {'entries': effects})
    classification = build_registry(ja, en, names, effects,
                                    read_json(home / REGISTRY_FILE, {'entries': []})['entries'])
    write_json(home / REGISTRY_FILE, common | {'policy_date': '2026-10-12', 'entries': classification})
    return dict(character_locks=sum(r['kind'] in PROPER_KINDS for r in names),
                unclassified_actors=sum(r['kind'] not in PROPER_KINDS for r in names),
                effect_or_title_candidates=len(effects), classified_name_ids=len(classification),
                source_manifest_sha256=fingerprint)


def audit_rows(rows, ja, en, names, effects, glossary, classifications=None):
    findings, seen = [], set()
    name_ids = {r['id']: r for r in names}
    effect_ids = {r['id']: r for r in effects}
    # Derive only structurally explicit labels when no saved classification was supplied.
    classifications = classifications if classifications is not None else build_registry(ja, en, names, effects)
    classification_ids = {r['id']: r for r in classifications}
    protected = {}
    def add(key, severity, code, message):
        findings.append(dict(id=key, severity=severity, code=code, message=message))
    if len(classification_ids) != len(classifications):
        add('', 'error', 'NAME_POLICY_DUPLICATE', 'ID lặp trong bảng phân loại tên.')
    for name in names:
        if name['kind'] not in PROPER_KINDS:
            continue
        policy = classification_ids.get(name['id'], {})
        if policy.get('name_kind') == 'role_name' and policy.get('review_status') == 'reviewed':
            continue
        source, lock = name['source_ja'], name['locked_name']
        if source in protected and protected[source] != lock:
            add(name['id'], 'error', 'NAME_REGISTRY_CONFLICT', 'Một tên JP bị khóa thành hai cách viết khác nhau.')
        protected[source] = lock
    for row in rows:
        key = row.get('id', '')
        source = row.get('text_ja', row.get('source_ja', ''))
        target = row.get('text_vi', '')
        if key in seen:
            add(key, 'error', 'DUPLICATE_ID', 'ID lặp trong đầu vào.')
        seen.add(key)
        if key not in ja or source != ja.get(key):
            add(key, 'error', 'SOURCE_MISMATCH', 'ID/nguồn JP không khớp archive gốc hiện tại.')
            continue
        error = validate_translation(source, target)
        if error:
            add(key, 'error', 'TOKENS', error)
        if not isinstance(target, str):
            continue
        classification = classification_ids.get(key)
        if not classification and key.startswith(('card@name@', 'assult_tactical_skill_title@')):
            add(key, 'error', 'NAME_POLICY_MISSING', 'Thiếu phân loại cho mục tên đã xác định.')
        findings.extend(name_findings(key, source, target, en.get(key, ''), classification))
        if Counter(HASH_VARS.findall(source)) != Counter(HASH_VARS.findall(target)):
            add(key, 'error', 'HASH_VARIABLES', 'Biến #...# thiếu, thêm hoặc bị đổi.')
        if Counter(FORMULAS.findall(source)) != Counter(FORMULAS.findall(target)):
            add(key, 'error', 'FORMULA', 'Nội dung/thứ tự phép toán trong {cal}...{/} bị đổi.')
        if tag_balance(source) and not tag_balance(target):
            add(key, 'error', 'TAG_BALANCE', 'Thẻ mở/đóng mất cân bằng so với nguồn hợp lệ.')
        if key.startswith(MECHANICS) and not mechanic_numbers_match(source, target):
            # 全て減少 literally means fully reduced; an explicit zero may be
            # defensible but requires meaning review, never automatic approval.
            if (numbers(target) - numbers(source) == Counter({'0': 1}) and
                    not numbers(source) - numbers(target) and '全て減少' in source):
                add(key, 'warning', 'NUMERIC_EXPLICITATION', 'JP nói giảm hết; VI thêm số 0. Cần duyệt nghĩa/đích chỉ số.')
            else:
                add(key, 'error', 'MECHANIC_NUMBERS', 'Chữ số cơ chế bị thay đổi; kiểm tra cả vai trò/đơn vị của số.')
        name = name_ids.get(key)
        is_reviewed_role = (classification and classification.get('name_kind') == 'role_name'
                            and classification.get('review_status') == 'reviewed')
        if name and name['kind'] in PROPER_KINDS and not is_reviewed_role:
            if name.get('source_changed') or name['source_ja'] != source:
                add(key, 'error', 'NAME_SOURCE_CHANGED', 'Registry tên đổi nguồn; cần đối chiếu lại.')
            if target != name['locked_name']:
                add(key, 'error', 'CHARACTER_NAME', 'Tên cần giữ nguyên: ' + name['locked_name'])
        elif name and not is_reviewed_role and visible(source).strip() and target != source:
            add(key, 'warning', 'CLASSIFY_ACTOR', 'Actor chưa phân loại tên riêng/vai trò; cần ngữ cảnh.')
        source_plain, target_plain = visible(source), visible(target)
        if (en.get(key, '').strip() and target.strip() == en[key].strip() and source != en[key]
                and not (classification and classification.get('name_kind') in EN_ONLY_KINDS)
                and not (name and name['kind'] in PROPER_KINDS and not is_reviewed_role)
                and len(re.findall(r'[A-Za-z]+', target_plain)) >= 2):
            add(key, 'warning', 'EN_COPY_CANDIDATE', 'VI trùng EN ngoài tên đã miễn; cần đọc nghĩa, không tự kết luận mọi ứng viên là lỗi.')
        for proper, lock in protected.items():
            count = occurrences(proper, source_plain)
            if count and occurrences(lock, target_plain) < count:
                add(key, 'error', 'NAME_IN_SENTENCE', 'Tên trong câu bị đổi/mất: ' + proper + ' → ' + lock)
        effect = effect_ids.get(key)
        if effect and not (classification and classification.get('name_kind') in EN_ONLY_KINDS):
            if effect.get('source_changed') or effect['source_ja'] != source or effect['reference_en'] != en.get(key, ''):
                add(key, 'error', 'EFFECT_SOURCE_CHANGED', 'Mapping hiệu ứng không khớp nguồn JP/EN hiện tại.')
            if effect['kind'] in EFFECT_KINDS:
                english = effect['english_name']
                actual = HASH_VARS.sub('', TAGS.sub('', target)).strip()
                if english and english != english_alias(en.get(key, '')):
                    add(key, 'error', 'EN_ALIAS_ID', 'Tên EN không đúng văn bản của cùng ID.')
                if not english:
                    add(key, 'error', 'EN_ALIAS_MISSING', 'Thiếu tên EN có thể dùng; không tự đoán.')
                elif actual == '(' + english + ')':
                    add(key, 'error', 'VI_EFFECT_MISSING', 'Có tên Anh nhưng thiếu tên Việt trước ngoặc.')
                elif not actual.endswith(' (' + english + ')'):
                    add(key, 'error', 'BILINGUAL_EFFECT', 'Thiếu/sai hậu tố tên Anh: (' + english + ')')
                if effect.get('review_status') != 'reviewed':
                    add(key, 'warning', 'EFFECT_MEANING_REVIEW', 'Tên Việt/loại hiệu ứng đang là ứng viên, cần đọc duyệt JP.')
                elif effect.get('vi_name') and actual != effect['vi_name'] + ' (' + english + ')':
                    add(key, 'error', 'EFFECT_TERM', 'Tên hiển thị khác tên song ngữ đã duyệt.')
            elif effect['kind'] == 'title_candidate' and target != source:
                add(key, 'warning', 'CLASSIFY_TITLE', 'Tooltip chưa phân loại: hiệu ứng/keyword hay nhãn thường.')
        remaining = target_plain
        for proper, lock in protected.items():
            if proper == lock:
                remaining = re.sub(r'(?<![\u30a1-\u30ff])' + re.escape(proper) + r'(?![\u30a1-\u30ff])', '', remaining)
        if JAPANESE.search(remaining):
            add(key, 'warning', 'JAPANESE_REMAINS', 'Còn JP ngoài token/tên đã khóa; cần biên tập hoặc phân loại tên mới.')
        if unicodedata.normalize('NFC', target) != target or any(c in target for c in ('\u200b', '\ufeff')):
            add(key, 'warning', 'UNICODE', 'Cần rà NFC/ký tự vô hình; không sửa token bằng normalize hàng loạt.')
        if (source in glossary and not name and not effect and not
                (classification and classification.get('name_kind') in EN_ONLY_KINDS)
                and target.casefold() != glossary[source].casefold()):
            add(key, 'warning', 'TERM', 'Khác thuật ngữ hiện tại; kiểm tra ngữ cảnh: ' + glossary[source])
        if len(target) > max(90, len(source) * 2):
            add(key, 'warning', 'LAYOUT', 'Chuỗi dài hơn đáng kể; ghi vị trí để người chơi xem cắt chữ.')
    return findings


def write_csv(path, rows, fields):
    with path.open('w', encoding='utf-8-sig', newline='') as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction='ignore')
        writer.writeheader()
        writer.writerows(rows)


def audit(home, game, batch, output):
    inst, ja, en, fingerprint = inputs(home, game)
    input_path = batch or inst.catalog_file
    catalog_bytes = inst.catalog_file.read_bytes()
    catalog = json.loads(catalog_bytes.decode('utf-8-sig'))
    previous = {r['id']: r for r in catalog['entries']}
    input_bytes = input_path.read_bytes() if batch else catalog_bytes
    if input_path.suffix.lower() == '.csv':
        rows = list(csv.DictReader(io.StringIO(input_bytes.decode('utf-8-sig'))))
    else:
        data = json.loads(input_bytes.decode('utf-8-sig'))
        rows = data if isinstance(data, list) else data['entries']
    names_bytes = (home / 'TEN_NHAN_VAT.json').read_bytes()
    effects_bytes = (home / 'TEN_HIEU_UNG.json').read_bytes()
    glossary_bytes = (home / 'THUAT_NGU.json').read_bytes()
    classification_path = home / REGISTRY_FILE
    classification_bytes = classification_path.read_bytes() if classification_path.exists() else None
    classification_registry = json.loads(classification_bytes.decode('utf-8-sig')) if classification_bytes else None
    names = json.loads(names_bytes.decode('utf-8-sig'))
    effects = json.loads(effects_bytes.decode('utf-8-sig'))
    if not names or not effects:
        raise RuntimeError('Thiếu registry; chạy prepare trước.')
    findings = audit_rows(rows, ja, en, names['entries'], effects['entries'],
                          json.loads(glossary_bytes.decode('utf-8-sig'))['terms'],
                          classification_registry['entries'] if classification_registry else None)
    for label, registry in (('names', names), ('effects', effects)):
        if registry['source_manifest_sha256'] != fingerprint:
            findings.append(dict(id='', severity='error', code='REGISTRY_VERSION',
                                 message=label + ': fingerprint cũ; chạy prepare và rà source_changed.'))
    captured = [(input_path, input_bytes, 'input'), (inst.catalog_file, catalog_bytes, 'catalog'),
                (home / 'TEN_NHAN_VAT.json', names_bytes, 'names'),
                (home / 'TEN_HIEU_UNG.json', effects_bytes, 'effects'),
                (home / 'THUAT_NGU.json', glossary_bytes, 'glossary')]
    if classification_bytes is not None:
        captured.append((classification_path, classification_bytes, 'name_classification'))
        if classification_registry.get('source_manifest_sha256') != fingerprint:
            findings.append(dict(id='', severity='error', code='REGISTRY_VERSION', message='Phân loại tên dùng fingerprint cũ.'))
    changed_inputs = [label for path, data, label in captured if path.read_bytes() != data]
    input_changed = 'input' in changed_inputs
    if changed_inputs:
        findings.append(dict(id='', severity='warning', code='INPUT_CHANGED_DURING_AUDIT',
                             message='Đã đổi trong lúc audit: ' + ', '.join(changed_inputs) +
                                     '; báo cáo chỉ áp dụng cho snapshot lưu kèm.'))
    output = output or home / 'data/reports/quality' / ('audit-' + datetime.now().strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:6])
    if output.exists():
        raise ValueError('Thư mục minh chứng đã tồn tại; chọn tên mới để giữ báo cáo cũ.')
    output.mkdir(parents=True)
    snapshot_path = output / ('INPUT_SNAPSHOT' + input_path.suffix.lower())
    atomic_bytes(snapshot_path, input_bytes)
    for filename, content in [('TEN_NHAN_VAT_SNAPSHOT.json', names_bytes),
                              ('TEN_HIEU_UNG_SNAPSHOT.json', effects_bytes),
                              ('THUAT_NGU_SNAPSHOT.json', glossary_bytes)]:
        atomic_bytes(output / filename, content)
    baseline_path = snapshot_path
    if classification_bytes is not None:
        atomic_bytes(output / 'PHAN_LOAI_TEN_SNAPSHOT.json', classification_bytes)
    if batch:
        baseline_path = output / 'CATALOG_BASELINE.json'
        atomic_bytes(baseline_path, catalog_bytes)
    before_after = [dict(id=r.get('id', ''), source_ja=r.get('text_ja', r.get('source_ja', '')),
                         reference_en=en.get(r.get('id'), ''),
                         previous_vi=previous.get(r.get('id'), {}).get('text_vi', ''),
                         proposed_vi=r.get('text_vi', ''), category=r.get('category', '')) for r in rows]
    write_csv(output / 'TRUOC_SAU.csv', before_after,
              ['id', 'source_ja', 'reference_en', 'previous_vi', 'proposed_vi', 'category'])
    write_csv(output / 'LOI.csv', findings, ['id', 'severity', 'code', 'message'])
    report = dict(schema=1, time=now(), input=str(input_path.resolve()),
                  mode='batch' if batch else 'catalog_baseline', rows=len(rows),
                  errors=sum(r['severity'] == 'error' for r in findings),
                  warnings=sum(r['severity'] == 'warning' for r in findings),
                  counts_by_code=dict(Counter(r['code'] for r in findings)),
                  technical_checks_passed=not any(r['severity'] == 'error' for r in findings),
                  source_priority='ja', semantic_review='not_performed_by_script',
                  gameplay='pending_player', installed_by_this_audit=False,
                  input_changed_during_audit=input_changed, input_snapshot=snapshot_path.name)
    report['changed_inputs_during_audit'] = changed_inputs
    write_json(output / 'REVIEW.json', report)
    proof = dict(schema=1, source_manifest_sha256=fingerprint,
                 input_sha256=hashlib.sha256(input_bytes).hexdigest(), input_snapshot=snapshot_path.name,
                 catalog_baseline_sha256=hashlib.sha256(catalog_bytes).hexdigest(),
                 catalog_baseline_snapshot=baseline_path.name,
                 catalog_revision=catalog.get('revision', ''), command=sys.argv,
                 tool_sha256=sha(Path(__file__)), names_sha256=hashlib.sha256(names_bytes).hexdigest(),
                 effects_sha256=hashlib.sha256(effects_bytes).hexdigest(),
                 glossary_sha256=hashlib.sha256(glossary_bytes).hexdigest(),
                 registry_snapshots=['TEN_NHAN_VAT_SNAPSHOT.json', 'TEN_HIEU_UNG_SNAPSHOT.json',
                                     'THUAT_NGU_SNAPSHOT.json'],
                 core_tool_hashes={name: sha(home / 'tools' / name) for name in
                                   ['installer_core.py', 'czn_format.py']},
                 source_files=['text/ja/text.db', 'text/en/text.db'],
                 matching='ID exact; JP source exact; EN read from original archive, not proposal',
                 findings_sha256=sha(output / 'LOI.csv'), before_after_sha256=sha(output / 'TRUOC_SAU.csv'),
                 live_file_status=inst.status(), gameplay_evidence=[], time=now())
    proof['name_classification_sha256'] = (hashlib.sha256(classification_bytes).hexdigest()
                                            if classification_bytes else None)
    proof['name_classification_mode'] = 'saved_registry' if classification_bytes else 'derived_explicit_labels'
    write_json(output / 'MINH_CHUNG.json', proof)
    return report | {'output': str(output.resolve())}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--game', type=Path)
    sub = parser.add_subparsers(dest='action', required=True)
    sub.add_parser('prepare')
    context = sub.add_parser('context')
    context.add_argument('--prefix', required=True)
    context.add_argument('--limit', type=int, default=300)
    check = sub.add_parser('audit')
    choice = check.add_mutually_exclusive_group(required=True)
    choice.add_argument('--batch', type=Path)
    choice.add_argument('--catalog', action='store_true')
    check.add_argument('--output', type=Path)
    args = parser.parse_args()
    home = args.project.resolve()
    if args.action == 'prepare':
        result = prepare(home, args.game)
    elif args.action == 'audit':
        result = audit(home, args.game, args.batch, args.output)
    else:
        if not args.prefix or args.limit < 1:
            raise ValueError('Cần prefix cụ thể và limit dương.')
        inst, ja, en, fingerprint = inputs(home, args.game)
        keys = [key for key in ja if key.startswith(args.prefix)]
        if not keys:
            raise ValueError('Không có ID khớp prefix.')
        target = home / 'data/reports/quality' / ('context-' + uuid.uuid4().hex[:8] + '.json')
        target.parent.mkdir(parents=True, exist_ok=True)
        catalog = {r['id']: r for r in inst.catalog()['entries']}
        write_json(target, dict(source_manifest_sha256=fingerprint, prefix=args.prefix,
                               order='database order; not proven scene sequence',
                               entries=[dict(id=k, text_ja=ja[k], text_en=en.get(k, ''),
                                             current_vi=catalog.get(k, {}).get('text_vi', '')) for k in keys[:args.limit]]))
        result = dict(output=str(target), exported=min(len(keys), args.limit), matched=len(keys))
    print(json.dumps(result, ensure_ascii=False))
    return 2 if args.action == 'audit' and result['errors'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
