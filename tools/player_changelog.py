"""Player-facing translation release notes, resolved from exact source references.

This module only reads context. It never edits catalogs, acknowledges publication,
or infers a card's owner from digits in its ID.
"""
from __future__ import annotations

import hashlib
import html
import json
import re
from collections import Counter, defaultdict, deque
from pathlib import Path

SECTIONS = ['Cốt truyện và bản đồ', 'Sự kiện và tương tác', 'Nhân vật',
            'Thẻ bài và kỹ năng', 'Thị trấn', 'Quả cầu Zero',
            'Giao diện và tính năng', 'Nội dung khác']
INVALID = {'', 'none', '-1', '[]'}


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def plain(value, limit=None):
    value = html.unescape(str(value or ''))
    value = re.sub(r'\{cal\}.*?\{/\}', '〔giá trị〕', value, flags=re.S)
    value = re.sub(r'\$[^$]*\$|\^[^^]*\^', '〔thuật ngữ liên kết〕', value)
    value = re.sub(r'#[A-Za-z_][A-Za-z0-9_]*#|\{\d+\}', '〔giá trị〕', value)
    value = re.sub(r'<br\s*/?>|<p>', ' ', value, flags=re.I)
    value = re.sub(r'<[^>]*>|\[/?fc\]|\[/\]', '', value)
    value = re.sub(r'\s+', ' ', value.replace('\\n', ' ')).strip()
    return value if limit is None or len(value) <= limit else value[:limit - 1].rstrip() + '…'


def count_text(number):
    return f'{number:,}'.replace(',', '.')


def refs(value):
    if not isinstance(value, str) or value in INVALID:
        return []
    if value.startswith('[') and value.endswith(']'):
        return [x.strip() for x in value[1:-1].split(',') if x.strip() not in INVALID]
    return [value]


def content_type(identity, domain):
    if domain == 'story':
        return 'thoại và lời dẫn'
    parts = identity.split('@')
    table, field = parts[0], parts[1] if len(parts) > 1 else ''
    if table == 'unlock_condition_state':
        return 'điều kiện mở khóa tính năng'
    if table == 'combatant_trial':
        return 'hướng dẫn trải nghiệm nhân vật'
    if table == 'twon_research_node_level':
        return 'tên nhánh nghiên cứu' if field == 'title' else 'mô tả nghiên cứu'
    if 'voice' in table and field in {'voice_text', 'text'}:
        return 'thoại nhân vật'
    if field in {'name', 'title', 'class_name'} or 'title' in field:
        return 'tên và nhãn hiển thị'
    if field in {'desc', 'desc_outgame', 'desc_battle', 'eff_description', 'description'}:
        return 'mô tả và hướng dẫn'
    if table.startswith(('i_', 'evts')):
        return 'thoại, lời dẫn và lựa chọn'
    return 'chữ hiển thị'


class Context:
    def __init__(self, ja=None, en=None, values=None, names=None, source_hash=None, name_kinds=None):
        self.ja, self.en, self.values = ja or {}, en or {}, values or {}
        self.names = names or {}
        self.name_kinds = name_kinds or {}
        self.source_hash = source_hash
        self.index = defaultdict(list)
        self.parents = defaultdict(set)
        self.containers = {}
        self.scenes = {}
        self.row_groups = defaultdict(set)
        self.row_definitions = defaultdict(set)
        self.warnings = []
        self.source_files = {}
        self.card_names = {v for k, v in self.en.items() if k.startswith('card@name@') and v}

    def label(self, text_id, official=False):
        if text_id not in self.ja:
            return ''
        # Name references are exact IDs; only official card/skill labels prefer EN.
        value = self.en.get(text_id, '') if official else self.values.get(text_id, '')
        if not value or value == self.ja.get(text_id):
            value = self.en.get(text_id, '')
        return plain(value, 140)

    def add(self, text_id, info):
        if text_id in self.ja:
            self.index[text_id].append(info)

    def table(self, source_file, rows):
        family = source_file.rsplit('@', 1)[-1].removesuffix('.db')
        for row in rows:
            row_id = row.get('id', '')
            if row_id not in INVALID:self.row_definitions[row_id].add(source_file)
            if row.get('group', '') not in INVALID:
                self.row_groups[row_id].add(row['group'])
            name_id = next((row.get(k) for k in ['name', 'class_name', 'title', 'skill_title']
                            if row.get(k) in self.ja), '')
            label = self.label(name_id, family == 'card' or self.name_kinds.get(name_id) == 'skill_name')
            section, entity = '', label
            if family == 'story_map_chapter':
                section = SECTIONS[0]
                if row.get('type') == 'main_story' and row.get('number', '').isdigit():
                    entity = f"Chương {int(row['number'])}" + (' · ' + label if label else '')
                elif label:
                    entity = label
            elif family == 'story_map_node':
                section = SECTIONS[0]
            elif family in {'encounter', 'encounter_pack', 'encounter_set'}:
                section = SECTIONS[1]
            elif family == 'card':
                section = SECTIONS[3]
                entity = 'Thẻ ' + label if label else ''
            elif family in {'account_skill', 'fate_skill', 'assault_tactical_skill'}:
                if self.name_kinds.get(name_id) == 'skill_name':
                    section = SECTIONS[3];entity = 'Kỹ năng ' + label if label else ''
                else:
                    section = SECTIONS[7];entity = 'Nội dung chưa phân loại · ' + label if label else ''
            elif family in {'char_base', 'char_combatant', 'char_partner'}:
                section = SECTIONS[2]
                entity = self.names.get(row_id, '')
            elif family in {'stage', 'stage_map', 'stagecs', 'story_map_condition'}:
                section = SECTIONS[0]
                if family == 'stagecs' and label:
                    entity = 'Hiệu ứng khu vực · ' + label
                elif family == 'story_map_condition' and label:
                    entity = 'Điều kiện bản đồ · ' + label
            if section and entity:
                info = {'section': section, 'entity': entity, 'status': 'classification_pending' if entity.startswith('Nội dung chưa phân loại · ') else 'source_reference',
                        'evidence': [{'file': source_file, 'row': row_id, 'name_id': name_id}]}
                self.containers[(source_file, row_id)] = info
                for value in row.values():
                    for ref in refs(value):
                        self.add(ref, info)
            # Traverse only declared relationship fields. No numeric/prefix owner inference.
            for field, value in row.items():
                if 'link' in field or field == 'contents_multiple_link':
                    for ref in refs(value):
                        if ref not in self.ja:
                            self.parents[ref].add((source_file, row_id))
            # Explicit character ownership fields, when present in this source schema.
            if family in {'card', 'combatant_voice', 'supporter_voice', 'event_combatant_trial', 'account_skill', 'fate_skill', 'assault_tactical_skill'}:
                owner_fields = ['owner_link_char_base_id', 'ownable_link_char_base_id', 'link_char_base_id']
                owners = {self.names[x] for k in owner_fields for x in refs(row.get(k, '')) if x in self.names}
                if len(owners) == 1:
                    info = {'section': SECTIONS[2], 'entity': next(iter(owners)) + (' · ' + entity if entity else ''),
                            'status': 'explicit_owner_reference',
                            'evidence': [{'file': source_file, 'row': row_id, 'owner_fields': owner_fields}]}
                    for value in row.values():
                        for ref in refs(value):
                            self.add(ref, info)

    def ancestors(self, row_id):
        found, queue, seen = [], deque([(row_id, 0)]), set()
        while queue:
            current, depth = queue.popleft()
            if current in seen or depth > 4:
                continue
            seen.add(current)
            # Source links carry unqualified IDs. A collision across tables cannot
            # prove which object was referenced; retain unknown rather than guessing.
            if len(self.row_definitions.get(current, ())) > 1:
                continue
            for group in self.row_groups.get(current, ()):
                queue.append((group, depth + 1))
            for parent in self.parents.get(current, ()):
                info = self.containers.get(parent)
                if info and info['section'] in {SECTIONS[0], SECTIONS[1]}:
                    found.append(info)
                queue.append((parent[1], depth + 1))
        return found

    def script(self, source_file, actions, wanted):
        scene = Path(source_file).stem
        for action in actions:
            text_id = action.get('yuna')
            if text_id in wanted:
                self.scenes[text_id] = scene
                for info in self.ancestors(scene):
                    self.add(text_id, info | {'evidence': info['evidence'] + [{'file': source_file, 'yuna': text_id}]})

    def resolve(self, change):
        identity, domain = change['id'], change['domain']
        candidates = self.index.get(identity, [])
        if domain == 'story':
            candidates = candidates + self.ancestors(change.get('metadata', {}).get('scene', ''))
        owners = [c for c in candidates if c['status'] == 'explicit_owner_reference']
        if owners:
            owned_rows = {(e.get('file'), e.get('row')) for c in owners for e in c['evidence']}
            candidates = [c for c in candidates if c['status'] == 'explicit_owner_reference' or
                          not any((e.get('file'), e.get('row')) in owned_rows for e in c['evidence'])]
        unique = {(c['section'], c['entity']): c for c in candidates}
        if len(unique) == 1:
            return dict(next(iter(unique.values())))
        if len(unique) > 1:
            return {'section': SECTIONS[7], 'entity': 'Vị trí dùng chung hoặc có nhiều liên kết',
                    'status': 'ambiguous', 'evidence': [c['evidence'] for c in unique.values()]}
        table = identity.split('@')[0]
        # Exact text.db object name reference: no ownership claim.
        parts = identity.split('@')
        name_id = '@'.join([table, 'name', *parts[2:]]) if len(parts) > 2 else ''
        if table == 'card':
            label = self.label(name_id, True)
            return {'section': SECTIONS[3], 'entity': 'Thẻ ' + label if label else 'Thẻ chưa xác định tên',
                    'status': 'exact_name_reference' if label else 'unresolved',
                    'owner_status': 'not_established', 'evidence': [{'name_id': name_id}]}
        if table == 'combatant_trial':
            title = plain(self.en.get(name_id, ''))
            mentioned = [n for n in self.names.values() if re.match(r'^' + re.escape(n) + r"(?:\b|’s|'s)", title)]
            mentioned = sorted(set(mentioned))
            return {'section': SECTIONS[2], 'entity': 'Trải nghiệm nhân vật' +
                    (' · nội dung về ' + ', '.join(mentioned) if len(mentioned) == 1 else ' · chưa xác định nhân vật'),
                    'status': 'source_description_subject' if len(mentioned) == 1 else 'unresolved',
                    'evidence': [{'name_id': name_id, 'reference_en': self.en.get(name_id, '')}],
                    'mentioned_cards': self.mentioned_cards(self.en.get(name_id, ''))}
        if table == 'twon_research_node_level':
            # Same-ID title pairs describe levels. Group by actual title text, not numeric ID.
            title_id = '@'.join([table, 'title', *parts[2:]])
            title = self.label(title_id)
            base = re.sub(r'\s*Lv\.\s*\d+\.?$', '', title).strip()
            return {'section': SECTIONS[4], 'entity': 'Nghiên cứu · ' + base if base else 'Nghiên cứu thị trấn',
                    'status': 'exact_title_reference' if title else 'unresolved', 'evidence': [{'name_id': title_id}]}
        if table == 'zero_orb_season_skill':
            source = self.en.get(identity, '')
            match = re.match(r'^\[([^\]]+)\]', source)
            return {'section': SECTIONS[5], 'entity': 'Kỹ năng dự bị · ' + match[1] if match else 'Kỹ năng và nâng cấp Quả cầu Zero',
                    'status': 'source_named_reference' if match else 'unresolved', 'evidence': [{'source_id': identity}]}
        if domain == 'story':
            return {'section': SECTIONS[0], 'entity': 'Thoại cốt truyện · chưa xác định chương',
                    'status': 'unresolved', 'evidence': [{'scene': change.get('metadata', {}).get('scene', '')}]}
        if table.startswith(('i_', 'evts')) or identity in self.scenes:
            return {'section': SECTIONS[1], 'entity': 'Thoại và tương tác · chưa xác định bản đồ',
                    'status': 'unresolved', 'evidence': [{'source_scene': self.scenes.get(identity, '')}]}
        if table == 'stagecs':
            return {'section': SECTIONS[0], 'entity': 'Hiệu ứng khu vực', 'status': 'unresolved', 'evidence': []}
        if table.startswith('story_map'):
            return {'section': SECTIONS[0], 'entity': 'Nhãn và điều kiện trên bản đồ cốt truyện', 'status': 'unresolved', 'evidence': []}
        if table == 'unlock_condition_state':
            return {'section': SECTIONS[6], 'entity': 'Điều kiện mở khóa tính năng', 'status': 'content_location', 'evidence': []}
        locations = [('shop_', 'Cửa hàng · sản phẩm, trang phục và hướng dẫn mua'), ('gacha', 'Chiêu mộ · hướng dẫn, kết quả và xác suất'),
                     ('mail', 'Hòm thư · thông báo và nhận vật phẩm'), ('top_menu', 'Menu · tên màn hình và điều hướng'),
                     ('guide_', 'Hướng dẫn · thông báo và thao tác'), ('tt_outgame', 'Hướng dẫn · các tính năng ngoài trận'),
                     ('ui_cash', 'Cửa hàng · mua hàng và giới hạn mua'), ('ui_shop', 'Cửa hàng · vật phẩm và trang phục'),
                     ('ui_gacha', 'Chiêu mộ · thông báo và xác suất'), ('ui_setting', 'Cài đặt · tùy chọn trò chơi'),
                     ('keyboard', 'Cài đặt · phím điều khiển'), ('event_stock_company', 'Sự kiện · giao dịch cổ phiếu'),
                     ('ui_', 'Giao diện · thông báo và thao tác'), ('cash_shop', 'Cửa hàng · sản phẩm và gói mua')]
        if table == 'ui':
            return {'section': SECTIONS[6], 'entity': 'Giao diện · thông báo và thao tác', 'status': 'content_location', 'evidence': []}
        for prefix, entity in locations:
            if table.startswith(prefix):
                return {'section': SECTIONS[6], 'entity': entity, 'status': 'content_location', 'evidence': []}
        return {'section': SECTIONS[7], 'entity': 'Chữ hiển thị · chưa xác định vị trí', 'status': 'unresolved', 'evidence': []}

    def mentioned_cards(self, text):
        labels = []
        for span in re.findall(r'<(?:color_[^>]+|u)>(.*?)</(?:u)?>', text or '', re.S):
            label = plain(span).strip('[]【】')
            if label in self.card_names:
                labels.append(label)
        return sorted(set(labels))


def from_archive(archive, ja, en, home, delta, snapshot=None):
    from story_format import StoryTable
    source_hash = digest(archive.data)
    home = Path(home)
    names_doc = json.loads((home / 'TEN_NHAN_VAT.json').read_text('utf-8-sig')) if (home / 'TEN_NHAN_VAT.json').exists() else {}
    names = {}
    if names_doc.get('source_manifest_sha256') == source_hash:
        for row in names_doc.get('entries', []):
            if row.get('kind') in {'character_name', 'character_alias'} and row.get('source_ja') == ja.get(row['id']) and not row.get('source_changed') and row.get('review_status') == 'source_verified' and row.get('reference_en') == en.get(row['id']):
                if row['id'].startswith('char_base@name@'):
                    names[row['id'].rsplit('@', 1)[-1]] = row['locked_name']
    if snapshot is not None:
        values = snapshot['values']['text']
    else:
        rows = json.loads((home / 'data/translations.json').read_text('utf-8-sig')).get('entries', [])
        values = {r['id']: r['text_vi'] for r in rows if r.get('source_ja', r.get('text_ja')) == ja.get(r['id'])}
    name_kinds = {}
    registry_path = home / 'PHAN_LOAI_TEN.json'
    if registry_path.exists():
        from name_policy import name_findings
        registry = json.loads(registry_path.read_text('utf-8-sig'))
        if registry.get('source_manifest_sha256') == source_hash:
            for row in registry.get('entries', []):
                key = row.get('id', '')
                if row.get('name_kind') == 'skill_name' and not name_findings(key, ja.get(key, ''), row.get('official_en_name', ''), en.get(key, ''), row):
                    name_kinds[key] = 'skill_name'
    context = Context(ja, en, values, names, source_hash, name_kinds)
    if registry_path.exists():context.source_files['PHAN_LOAI_TEN.json'] = digest(registry_path.read_bytes())
    if (home / 'TEN_NHAN_VAT.json').exists():
        context.source_files['TEN_NHAN_VAT.json'] = digest((home / 'TEN_NHAN_VAT.json').read_bytes())
    families = {'story_map_chapter', 'story_map_node', 'story_map_contents', 'story_map_condition', 'story_map_text',
                'encounter', 'encounter_option', 'encounter_option_eff', 'encounter_pack', 'encounter_set',
                'stage', 'stage_map', 'stagecs', 'char_base', 'char_combatant', 'char_partner', 'combatant_info',
                'combatant_voice', 'supporter_voice', 'event_combatant_trial', 'card', 'fate_skill', 'account_skill', 'assault_tactical_skill'}
    for file in archive.files:
        if not file.startswith('db/') or '@' not in file or file.rsplit('@', 1)[-1].removesuffix('.db') not in families:
            continue
        try:
            raw = archive.read_file(file)
            table = StoryTable(raw)
            context.source_files[file] = digest(raw)
            context.table(file, [dict(zip(table.columns, table.values[key])) for key in table.order])
        except (OSError, ValueError) as error:
            context.warnings.append({'file': file, 'reason': type(error).__name__, 'status': 'context_unavailable'})
    wanted = {c['id'] for c in delta['changes'] if c['domain'] == 'text' and
              re.match(r'^(?:i_|evts|stys|trcs|e[0-9]+s|cs[0-9]+_|story_[0-9]+)', c['id'])}
    wanted_prefixes = tuple({k.split('@')[0].encode() + b'@' for k in wanted})
    if wanted:
        for file in archive.files:
            if not file.endswith('.sract') or not file.startswith('enact/'):
                continue
            try:
                raw = archive.read_file(file)
                if not any(t in raw for t in wanted_prefixes):
                    continue
                actions = json.loads(raw).get('actions', [])
                context.source_files[file] = digest(raw)
                context.script(file, actions, wanted)
            except (OSError, ValueError) as error:
                context.warnings.append({'file': file, 'reason': type(error).__name__, 'status': 'context_unavailable'})
    return context


def for_home(home, delta, snapshot=None, archive=None, ja=None):
    from czn_format import Database
    from installer_core import Installer, read_json
    home = Path(home)
    if (home / 'data/journal.json').exists():
        raise RuntimeError('Có giao dịch dang dở; không lấy ngữ cảnh trước khi phục hồi bằng bộ cài.')
    if archive is None:
        settings = read_json(home / 'data/settings.json', {})
        inst = Installer(home, Path(settings.get('game_dir', home.parent)), log=lambda _: None)
        archive, db = inst.original_archive()
        ja = db.texts
    if ja is None:
        ja = Database(archive.read_file('text/ja/text.db'), require_native_phase=True).texts
    en = Database(archive.read_file('text/en/text.db'), require_native_phase=True).texts
    return from_archive(archive, ja, en, home, delta, snapshot)


def model(delta, context=None, limit=10000):
    context = context or Context()
    changes = delta['changes']
    seen, rows, groups = set(), [], {}
    for change in changes:
        key = change['domain'], change['id']
        if key in seen:
            raise ValueError('ID thay đổi lặp; không thể tính thông báo chính xác.')
        seen.add(key)
        info = context.resolve(change)
        kind = 'thoại, lời dẫn và lựa chọn' if change['id'] in context.scenes else content_type(change['id'], change['domain'])
        row = dict(change, player_context=info, content_type=kind,
                   before_display=plain(change.get('before', '')), after_display=plain(change.get('after', '')))
        rows.append(row)
        group_key = info['section'], info['entity'], kind
        group = groups.setdefault(group_key, {'section': info['section'], 'entity': info['entity'],
                                              'content_type': kind, 'ids': [], 'kinds': Counter(), 'mentioned_cards': set()})
        group['ids'].append({'domain': change['domain'], 'id': change['id']})
        group['kinds'][change['kind']] += 1
        group['mentioned_cards'].update(info.get('mentioned_cards', []))
    ordered = sorted(groups.values(), key=lambda g: (SECTIONS.index(g['section']), -len(g['ids']), g['entity'], g['content_type']))
    for group in ordered:
        group['kinds'] = dict(group['kinds']);group['mentioned_cards'] = sorted(group['mentioned_cards'])
    counts = Counter(c['kind'] for c in changes)
    base = delta['baseline_version']
    if not changes:
        text = 'Không có thay đổi bản dịch so với bản đã phát hành ' + base + '.'
    else:
        lines = ['Nội dung cập nhật bản dịch so với bản ' + base + ':',
                 f"Thêm tiếng Việt: {count_text(counts['new'])} dòng; sửa bản dịch: {count_text(counts['edited'])} dòng; ngừng áp dụng: {count_text(counts['removed'])} dòng.",
                 'Các mục dưới đây chỉ nói về chữ hiển thị được thay đổi, không có nghĩa toàn bộ chế độ đã Việt hóa.']
        # Keep every section visible. Merge an entity's name/description groups in
        # the short notice; every exact ID remains available in the detail model.
        display = {}
        for group in ordered:
            item = display.setdefault((group['section'], group['entity']),
                      {'types': [], 'kinds': Counter(), 'cards': set(), 'size': 0})
            item['types'].append(group['content_type'])
            item['kinds'].update(group['kinds'])
            item['cards'].update(group['mentioned_cards'])
            item['size'] += len(group['ids'])
        trial = [(key, item) for key, item in display.items() if key[0] == SECTIONS[2] and key[1].startswith('Trải nghiệm nhân vật · nội dung về ')]
        if trial:
            merged = {'types': [], 'kinds': Counter(), 'cards': set(), 'size': 0}
            subjects = []
            for key, item in trial:
                subjects.append(key[1].removeprefix('Trải nghiệm nhân vật · nội dung về '))
                for kind in item['types']:
                    if kind not in merged['types']:merged['types'].append(kind)
                merged['kinds'].update(item['kinds']);merged['cards'].update(item['cards']);merged['size'] += item['size']
                del display[key]
            display[(SECTIONS[2], 'Trải nghiệm nhân vật · nội dung về ' + ', '.join(sorted(subjects)))] = merged
        active_sections = [section for section in SECTIONS if any(k[0] == section for k in display)]
        budget = max(100, (limit - len('\n'.join(lines)) - 300) // max(1, len(active_sections)))
        omitted = []
        for section in active_sections:
            lines.append('\n' + section + ':')
            used = 0
            section_items = [(entity, item) for (sec, entity), item in display.items() if sec == section]
            if section == SECTIONS[0]:
                section_items.sort(key=lambda pair: (pair[0].startswith(('Hiệu ứng khu vực · ', 'Điều kiện bản đồ · ')), not pair[0].startswith('Chương '), -pair[1]['size'], pair[0]))
            for entity, item in section_items:
                parts = []
                for kind, label in [('new', 'thêm tiếng Việt'), ('edited', 'sửa bản dịch'), ('removed', 'ngừng áp dụng')]:
                    if item['kinds'].get(kind):parts.append(label + ' ' + count_text(item['kinds'][kind]) + ' dòng')
                line = '• ' + entity + ': ' + ', '.join(item['types']) + ' — ' + '; '.join(parts) + '.'
                cards = sorted(item['cards'])
                if cards:line += ' Thẻ được nhắc tới: ' + ', '.join(cards[:5]) + (f' và {len(cards)-5} thẻ khác' if len(cards)>5 else '') + '.'
                if used + len(line) + 1 <= budget and len('\n'.join(lines + [line])) + 220 <= limit:
                    lines.append(line);used += len(line) + 1
                else:
                    omitted.append(item)
        if omitted:
            lines.append(f"• {len(omitted)} nhóm còn lại: {count_text(sum(g['size'] for g in omitted))} dòng. Xem danh sách chi tiết trong bộ cài.")
        text = '\n'.join(lines)
    return {'schema': 1, 'baseline_version': base, 'text': text, 'counts': dict(counts),
            'groups': ordered, 'changes': rows, 'source_manifest_sha256': context.source_hash,
            'context_source_files': context.source_files, 'context_warnings': context.warnings,
            'unresolved_changes': sum(r['player_context']['status'] in {'unresolved', 'ambiguous', 'classification_pending'} for r in rows),
            'scope': 'Only exact changed IDs; source-linked names, unknown associations explicitly retained; no gameplay changes claimed.'}
