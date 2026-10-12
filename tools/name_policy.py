"""Per-ID name classification. Never classify every 'skill' or 'card' field as a name."""
import re
from czn_format import TOKENS

REGISTRY_FILE = 'PHAN_LOAI_TEN.json'
EN_ONLY_KINDS = {'card_name', 'skill_name'}
READY_STATUSES = {'source_verified', 'reviewed'}
SKILL_CANDIDATE_TABLES = {'zero_skill', 'zero_system_skill', 'fate_skill',
                         'zero_orb_skill', 'collapse_skill', 'account_skill'}
KINDS = EN_ONLY_KINDS | {'character_name', 'character_alias', 'effect_name',
                        'keyword', 'role_name', 'unclassified_name', 'skill_candidate',
                        'condition_label', 'linked_label', 'dynamic_value_label', 'ui_label'}


def literal_name(text):
    """Literal comparison only; token identities are checked separately by the auditor."""
    return re.sub(r'\s+', ' ', TOKENS.sub(' ', text)).strip()


def display_policy(kind):
    if kind in EN_ONLY_KINDS:
        return 'official_en_only'
    if kind in {'character_name', 'character_alias'}:
        return 'locked_character_name'
    if kind in {'effect_name', 'keyword'}:
        return 'vi_plus_en'
    if kind in {'role_name', 'condition_label', 'ui_label'}:
        return 'translate_vi'
    return 'pending_classification'


def build_registry(ja, en, names, effects, previous=None):
    """Strong schema evidence for card/tactical names; ambiguous skill tables stay pending."""
    records = {}
    for row in names:
        kind = row.get('kind', 'unclassified_name')
        if kind not in {'character_name', 'character_alias', 'role_name'}:
            kind = 'unclassified_name'
        records[row['id']] = (kind, row.get('review_status', 'candidate'), row.get('evidence', ''))
    for row in effects:
        kind = row.get('kind', '')
        if kind == 'effect_or_keyword_candidate':
            kind = 'unclassified_name'
        if kind not in KINDS:
            kind = 'unclassified_name'
        records[row['id']] = (kind, row.get('review_status', 'candidate'), row.get('evidence', ''))
    for key in ja:
        if key.startswith('card@name@'):
            records[key] = ('card_name', 'source_verified', 'Explicit card@name label; EN exact same ID')
        elif key.startswith('assult_tactical_skill_title@'):
            records[key] = ('skill_name', 'source_verified', 'Named tactical skill title table; EN exact same ID')
        elif key.split('@')[0] in SKILL_CANDIDATE_TABLES and 'name' in key:
            records.setdefault(key, ('skill_candidate', 'candidate',
                                    'May be skill, status, perk or operation; inspect referent before locking'))
    prior = {r['id']: r for r in previous or []}
    result = []
    for key, (kind, status, evidence) in sorted(records.items()):
        source, reference = ja.get(key, ''), en.get(key, '')
        old = prior.get(key, {})
        changed = bool(old and (old.get('source_ja') != source or old.get('reference_en') != reference or
                               old.get('source_changed') and old.get('review_status') != 'reviewed'))
        record = dict(id=key, source_ja=source, reference_en=reference, name_kind=kind,
                      display_policy=display_policy(kind), official_en_name=literal_name(reference),
                      review_status=status, classification_evidence=evidence, source_changed=changed)
        if old.get('review_status') == 'reviewed' and not changed:
            for field in ('name_kind', 'review_status', 'classification_evidence', 'referent_ids', 'reviewer'):
                if field in old:
                    record[field] = old[field]
            record['display_policy'] = display_policy(record['name_kind'])
        if changed:
            record['review_status'] = 'pending_source_review'
        if record['name_kind'] in EN_ONLY_KINDS and not record['official_en_name']:
            record['review_status'] = 'pending_missing_en'
        result.append(record)
    return result


def name_findings(key, source, target, reference, record):
    if not record:
        return []
    result = []
    def add(severity, code, message):
        result.append(dict(id=key, severity=severity, code=code, message=message))
    if record.get('source_changed') or record.get('source_ja') != source or record.get('reference_en') != reference:
        add('error', 'NAME_POLICY_SOURCE', 'Phân loại tên không khớp JP/EN hiện tại; cần rà nguồn.')
    kind = record.get('name_kind')
    if kind not in KINDS:
        add('error', 'NAME_POLICY_KIND', 'Loại tên không hợp lệ.')
    if record.get('display_policy') != display_policy(kind):
        add('error', 'NAME_POLICY_RULE', 'Quy tắc hiển thị khác loại tên đã phân loại.')
    if kind in EN_ONLY_KINDS:
        expected = literal_name(reference)
        if not expected:
            add('error', 'NAME_EN_MISSING', 'Thiếu tên EN chính thức cùng ID; không tự đặt tên.')
        if record.get('official_en_name') != expected:
            add('error', 'NAME_EN_MAPPING', 'Tên EN trong registry sai nguồn cùng ID.')
        if record.get('review_status') not in READY_STATUSES:
            add('error', 'NAME_CLASSIFICATION_PENDING', 'Tên chưa đủ điều kiện khóa; cần phân loại/rà nguồn.')
        if record.get('review_status') == 'source_verified' and not key.startswith(('card@name@', 'assult_tactical_skill_title@')):
            add('error', 'NAME_CLASSIFICATION_PENDING', 'Nhãn mơ hồ cần reviewer xác minh, không suy từ chữ skill.')
        if record.get('review_status') == 'reviewed' and not (record.get('reviewer') and record.get('classification_evidence')):
            add('error', 'NAME_CLASSIFICATION_PENDING', 'Thiếu reviewer hoặc chứng cứ phân loại thủ công.')
        if expected and literal_name(target) != expected:
            add('error', 'NAME_EN_ONLY', 'Tên kỹ năng/thẻ chỉ dùng EN chính thức: ' + expected)
    return result
