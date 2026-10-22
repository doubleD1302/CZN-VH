"""Local text resource reader/writer. No executable or gameplay changes.

SSRA/PLPcK layout reference (MIT):
https://github.com/cznrip/Chaos-Zero-Nightmare-ASSet-Ripper
"""
from __future__ import annotations
from dataclasses import dataclass
from pathlib import Path
import re
import struct
import sys

sys.path.insert(0, str(Path(__file__).parent / 'vendor'))
import xxhash
import zstandard as zstd

KEY = bytes.fromhex(
    '91AE4ED4644F585162EC1BD5EF24ADDBAF838242AEF51E97804B134FFD8CE5BB4F6E3E6451147CDF56C318E5E964C999C0D95CC860822E6B418BE465D79A036DBF67AB3DA72AB1023A4561F444E5CE858D23EA10FEB4899151AD7E43FF3E2419A97B4DD3AF4EF5C829E5AF4ACE9436F6B6B6382E9DFD26642099011A4899089C9D4B9F80BBB00A4CC73255CE1F78646E91C9C12313F5D840DC51457010D37D19615BB69888B42B19E749F993C00337E9332F89B320C173A5653848788798A771739E72DBC84C7946597149BDDAE4E3BD1A17856C85A555CFA24F6352D005933B50042BE0BA4C708DE8EBB52059B2059C9BFE90D8923DF74B43911BBC00BB6BFA'
)


class FormatError(ValueError):
    pass


class MissingChunkError(FormatError, RuntimeError):
    def __init__(self, chunk_name, message):
        self.chunk_name = chunk_name
        super().__init__(message)


def u40(data, pos):
    return (data[pos] << 32) | struct.unpack_from('<I', data, pos + 1)[0]


def put40(data, pos, value):
    if not 0 <= value < 1 << 40:
        raise FormatError('Con trỏ cơ sở dữ liệu vượt giới hạn.')
    data[pos] = value >> 32
    struct.pack_into('<I', data, pos + 1, value & 0xffffffff)


def xor_bytes(data, key):
    # bytes.translate handles the 256 interleaved lanes in native code.
    result = bytearray(len(data))
    identity = bytes(range(256))
    for i, k in enumerate(key):
        result[i::256] = data[i::256].translate(bytes(x ^ k for x in identity))
    return bytes(result)


@dataclass
class Record:
    offset: int
    size: int
    kind: int
    name: str
    next: int
    value: bytes


class Database:
    def __init__(self, encrypted, require_native_phase=False):
        if len(encrypted) < 38:
            raise FormatError('Cơ sở dữ liệu quá ngắn.')
        rotation = len(encrypted) % 256 if require_native_phase else next((i for i in range(256) if all(
            encrypted[j] ^ KEY[(i + j) % 256] == b'PLPcK'[j] for j in range(5)
        )), None)
        if rotation is None or bytes(encrypted[j] ^ KEY[(rotation + j) % 256] for j in range(5)) != b'PLPcK':
            raise FormatError('Định dạng mã hóa bảng văn bản chưa được hỗ trợ.')
        self.phase = rotation
        self.key = KEY[rotation:] + KEY[:rotation]
        self.data = xor_bytes(encrypted, self.key)
        d = self.data
        if d[:5] != b'PLPcK' or d[5] != 1 or struct.unpack_from('<H', d, 6)[0] != 38:
            raise FormatError('Phiên bản PLPcK chưa được hỗ trợ.')
        self.count, self.buckets = struct.unpack_from('<II', d, 17)
        self.ht = u40(d, 25)
        if self.buckets > 2000000 or self.ht + 5 + self.buckets * 5 > len(d):
            raise FormatError('Bảng băm không hợp lệ.')
        if struct.unpack_from('<IB', d, self.ht) != (5 * (self.buckets + 1), 1):
            raise FormatError('Bảng gốc không hợp lệ.')
        self.records = {}
        self.bucket_heads = []
        visited = set()
        for bucket in range(self.buckets):
            pos = u40(d, self.ht + 5 + bucket * 5)
            self.bucket_heads.append(pos)
            while pos:
                if pos in visited or pos + 15 > len(d):
                    raise FormatError('Liên kết bảng văn bản bị lỗi hoặc trùng.')
                visited.add(pos)
                size, kind, name_len, val_len = struct.unpack_from('<IBBI', d, pos)
                nxt = u40(d, pos + 10)
                end = pos + size
                if kind != 2 or size != 15 + name_len + val_len or end > len(d):
                    raise FormatError('Bản ghi văn bản bị cắt hoặc có kiểu chưa hỗ trợ.')
                name = d[pos + 15:pos + 15 + name_len].decode('utf-8')
                if name in self.records:
                    raise FormatError('Khóa văn bản bị trùng: ' + name)
                self.records[name] = Record(pos, size, kind, name, nxt, d[pos + 15 + name_len:end])
                pos = nxt
        if len(self.records) != self.count:
            raise FormatError('Số bản ghi không khớp phần đầu dữ liệu.')
        self.rows = self._integer('\trows')
        cols = self._integer('\tcols')
        if cols != 2 or self.records['\t0'].value != b'id' or self.records['\t1'].value != b'text':
            raise FormatError('Cấu trúc cột ngôn ngữ đã thay đổi.')
        self.texts = {}
        self.order = []
        for i in range(self.rows):
            key = self.records['\t\t' + str(i)].value.decode('utf-8')
            values = self.records[key].value.split(b'\0')
            if len(values) != 3 or values[-1] != b'' or values[0].decode('utf-8') != key:
                raise FormatError('Dữ liệu hàng văn bản không hợp lệ: ' + key)
            self.texts[key] = values[1].decode('utf-8')
            self.order.append(key)
        if len(self.texts) != self.rows:
            raise FormatError('ID hàng bị trùng.')

    def _integer(self, key):
        if key not in self.records or len(self.records[key].value) != 4:
            raise FormatError('Thiếu siêu dữ liệu bảng văn bản.')
        return struct.unpack('<I', self.records[key].value)[0]

    def rebuild(self, translations):
        unknown = set(translations) - self.texts.keys()
        if unknown:
            raise FormatError('Bản dịch chứa ID không thuộc phiên bản game này.')
        ordered = sorted(self.records.values(), key=lambda r: r.offset)
        prefix = min(r.offset for r in ordered)
        if prefix < self.ht + 5 + self.buckets * 5:
            raise FormatError('Bản ghi chồng lên bảng băm.')
        result = bytearray(self.data[:prefix])
        relocated = {}
        pending = []
        for r in ordered:
            name = r.name.encode('utf-8')
            value = r.value
            if r.name in translations:
                text = translations[r.name]
                if '\0' in text:
                    raise FormatError('Bản dịch chứa ký tự NUL.')
                value = name + b'\0' + text.encode('utf-8') + b'\0'
            pos = len(result)
            relocated[r.offset] = pos
            result += struct.pack('<IBBI', 15 + len(name) + len(value), r.kind, len(name), len(value))
            result += bytes(5) + name + value
            pending.append((pos + 10, r.next))
        for p, old in pending:
            put40(result, p, relocated[old] if old else 0)
        for i, old in enumerate(self.bucket_heads):
            put40(result, self.ht + 5 + i * 5, relocated[old] if old else 0)
        # The engine derives the XOR start from the NEW uncompressed byte length.
        # Preserving the original phase works in a phase-detecting extractor, but
        # makes the native client fail to load every localization row.
        phase = len(result) % len(KEY)
        encrypted = xor_bytes(bytes(result), KEY[phase:] + KEY[:phase])
        check = Database(encrypted, require_native_phase=True)
        expected = self.texts | translations
        if check.texts != expected or check.order != self.order or check.count != self.count:
            raise FormatError('Kiểm tra sau đóng gói không khớp văn bản gốc.')
        return encrypted


class Archive:
    def __init__(self, resource_dir, manifest_path=None, chunk_overrides=None):
        self.root = Path(resource_dir)
        self.manifest_path = Path(manifest_path) if manifest_path else self.root / 'manifest.ssra'
        self.data = self.manifest_path.read_bytes()
        self.overrides = chunk_overrides or {}
        d = self.data
        if len(d) < 64:
            raise FormatError('Manifest quá ngắn.')
        magic, ver, header, nc, nf, flags, so, ss, co, fo, extra = struct.unpack_from('<4s5I5Q', d)
        if magic != b'SSRA' or ver != 4 or header != 88:
            raise FormatError('Game dùng phiên bản SSRA chưa được hỗ trợ; dữ liệu gốc được giữ nguyên.')
        if nc > 65535 or nf > 2000000 or max(co + nc * 32, fo + nf * 40, so + ss + 16) > len(d):
            raise FormatError('Manifest có bảng chỉ mục không hợp lệ.')
        self.file_table = fo
        self.chunk_table = co
        self.file_count = nf
        self.groups = {}
        gpos = so + ss
        if d[gpos:gpos + 4] != b'GRPS':
            raise FormatError('Không tìm thấy nhóm tài nguyên.')
        ng, gs = struct.unpack_from('<II', d, gpos + 4)
        names = gpos + 16 + ng * 24
        if names + gs > len(d):
            raise FormatError('Bảng tên nhóm không hợp lệ.')
        for i in range(ng):
            pos = gpos + 16 + i * 24
            gid = struct.unpack_from('<H', d, pos)[0]
            name_off = struct.unpack_from('<I', d, pos + 4)[0]
            self.groups[gid] = d[names + name_off:d.index(0, names + name_off, names + gs)].decode('utf-8')
        self.chunks = []
        cumulative = {}
        for i in range(nc):
            cid, gid, unk, size, total, checksum = struct.unpack_from('<IHHQQQ', d, co + i * 32)
            group = self.groups.get(gid, '')
            filename = f'{group}_b{cid:02d}_0.ssrc'
            # CNAM lists exact physical names in modern manifests.
            self.chunks.append(dict(index=i, gid=gid, id=cid, size=size, total=total,
                                    checksum=checksum, start=cumulative.get(gid, 0), name=filename))
            cumulative[gid] = cumulative.get(gid, 0) + size
        for gid in self.groups:
            start = 0
            for chunk in sorted((c for c in self.chunks if c['gid'] == gid), key=lambda c: c['id']):
                chunk['start'] = start
                start += chunk['size']
        cnam = names + gs
        self.fhash = None
        st = d[so:so + ss]
        if d[cnam:cnam + 4] == b'CNAM':
            cnt, reserved, namesize = struct.unpack_from('<III', d, cnam + 4)
            if cnt != nc or reserved != 0:
                raise FormatError('Bảng tên chunk không hợp lệ.')
            # A zero namesize means offsets into the manifest string table,
            # not absent names. Chunk IDs need not match physical filenames.
            cnames = cnam + 16 + cnt * 8
            if cnames + namesize > len(d):
                raise FormatError('Bảng tên chunk vượt manifest.')
            name_table = d[cnames:cnames + namesize] if namesize else st
            seen_indices, seen_names = set(), set()
            for i in range(cnt):
                ci, no = struct.unpack_from('<II', d, cnam + 16 + i * 8)
                if ci >= nc or ci in seen_indices or no >= len(name_table):
                    raise FormatError('Chỉ mục tên chunk không hợp lệ hoặc bị trùng.')
                end = name_table.find(b'\0', no)
                if end < 0:
                    raise FormatError('Tên chunk thiếu ký tự kết thúc.')
                try:
                    name = name_table[no:end].decode('utf-8')
                except UnicodeDecodeError as error:
                    raise FormatError('Tên chunk không phải UTF-8 hợp lệ.') from error
                if (not name or name in ('.', '..') or Path(name).name != name
                        or any(x in name for x in '/\\:') or not name.endswith('.ssrc')
                        or name.casefold() in seen_names):
                    raise FormatError('Tên chunk không an toàn hoặc bị trùng.')
                seen_indices.add(ci)
                seen_names.add(name.casefold())
                self.chunks[ci]['name'] = name
            search_from = cnames + namesize
        else:
            search_from = cnam
        hp = d.find(b'FHSH', search_from)
        if hp < 0 or hp + 16 + nf * 8 != len(d):
            raise FormatError('Bảng checksum file chưa được hỗ trợ.')
        fcount, algo, reserved = struct.unpack_from('<III', d, hp + 4)
        if fcount != nf or algo != 1 or reserved != 0:
            raise FormatError('Thuật toán checksum file chưa được hỗ trợ.')
        self.fhash = hp + 16
        self.files = {}
        st = d[so:so + ss]
        for i in range(nf):
            pos = fo + i * 40
            ph, unk, offset, cs, us, unk2, no, comp, enc, gid, fflags = struct.unpack_from('<IIQIIIIBBHI', d, pos)
            if no >= len(st):
                raise FormatError('Địa chỉ tên file không hợp lệ.')
            name = st[no:st.index(0, no)].decode('utf-8').strip('/').replace('\\', '/')
            if fflags & 1:
                continue
            self.files[name] = dict(index=i, entry=pos, off=offset, cs=cs, us=us,
                                   comp=comp, enc=enc, gid=gid, name=name)
        if 'text/ja/text.db' not in self.files:
            raise FormatError('Chưa có tài nguyên chữ tiếng Nhật. Hãy tải ngôn ngữ Nhật trong game trước.')
        self._cache = {}

    def chunk_bytes(self, chunk):
        name = chunk['name']
        if name not in self._cache:
            p = Path(self.overrides.get(name, self.root / 'chunks' / name))
            # Never substitute a same-sized file: the writer and the native
            # game must address the exact same physical name from CNAM.
            if not p.is_file():
                if name.startswith('lang_ja_'):
                    raise MissingChunkError(name,
                        f'Chưa phát hiện gói dữ liệu Tiếng Nhật trong game ({name}). '
                        'Hãy mở game CZN lên, vào Cài đặt ➔ Ngôn ngữ chọn 日本語 (Tiếng Nhật) để game tải dữ liệu trước, rồi quay lại đây bấm Cài Tiếng Việt nhé.'
                    )
                raise MissingChunkError(name,
                    f'Game chưa tải đủ tệp dữ liệu ({name}). '
                    'Hãy mở game để tải đủ dữ liệu cập nhật, hoặc bấm Kiểm tra tệp tin trên STOVE.'
                )
            data = p.read_bytes()
            p_bak = Path(str(p) + '.bak')
            if p_bak.exists():
                h_test = xxhash.xxh64_intdigest(data[:-16]) if len(data) >= 16 else 0
                if len(data) != chunk['total'] or h_test != chunk['checksum']:
                    data = p_bak.read_bytes()
            if len(data) != chunk['total'] or chunk['total'] != chunk['size'] + 16:
                raise FormatError('Kích thước chunk không khớp: ' + name)
            if data[-16:-8] != b'SSRC' + struct.pack('<I', chunk['id']):
                raise FormatError('Phần cuối chunk không hợp lệ: ' + name)
            h = xxhash.xxh64_intdigest(data[:-16])
            if h != chunk['checksum'] or h != struct.unpack_from('<Q', data, len(data) - 8)[0]:
                raise FormatError('Checksum chunk không khớp: ' + name + '. Hãy hoàn tất cập nhật/kiểm tra file bằng STOVE.')
            self._cache[name] = data
        return self._cache[name]

    def segments(self, file):
        cursor, remaining = file['off'], file['cs']
        pieces = []
        for c in sorted((x for x in self.chunks if x['gid'] == file['gid']), key=lambda x: x['start']):
            if c['gid'] != file['gid'] or not c['start'] <= cursor < c['start'] + c['size']:
                continue
            n = min(remaining, c['start'] + c['size'] - cursor)
            pieces.append((c, cursor - c['start'], n))
            cursor += n
            remaining -= n
            if not remaining:
                return pieces
        raise FormatError('Không tìm thấy đủ chunk cho bảng ngôn ngữ.')

    def read_file(self, name):
        f = self.files[name]
        if f['enc']:
            raise FormatError('Lớp mã hóa tài nguyên chưa được hỗ trợ.')
        raw = b''.join(self.chunk_bytes(c)[off:off + n] for c, off, n in self.segments(f))
        if f['comp']:
            if raw[:4] in (b'\x25\xb5\x2f\xfd', b'\x26\xb5\x2f\xfd', b'\x27\xb5\x2f\xfd'):
                raw = b'\x28' + raw[1:]
            raw = zstd.ZstdDecompressor().decompress(raw, max_output_size=f['us'], allow_extra_data=False)
        if len(raw) != f['us']:
            raise FormatError('Độ dài giải nén không khớp manifest.')
        expected = struct.unpack_from('<Q', self.data, self.fhash + f['index'] * 8)[0]
        if xxhash.xxh64_intdigest(raw) != expected:
            raise FormatError('Checksum bảng văn bản không khớp.')
        return raw

    def patch_text(self, translations, output):
        f = self.files['text/ja/text.db']
        source = Database(self.read_file(f['name']))
        encrypted = source.rebuild(translations)
        compressed = None
        for level in (9, 15, 19):
            candidate = zstd.ZstdCompressor(level=level, write_checksum=True).compress(encrypted)
            if len(candidate) <= f['cs']:
                compressed = candidate
                break
        if compressed is None:
            raise FormatError('Bản dịch vượt dung lượng vùng ngôn ngữ. Chưa ghi thay đổi vào game.')
        assert zstd.ZstdDecompressor().decompress(compressed, allow_extra_data=False) == encrypted
        output = Path(output)
        (output / 'chunks').mkdir(parents=True, exist_ok=True)
        manifest = bytearray(self.data)
        stream = compressed + bytes(f['cs'] - len(compressed))
        cursor = 0
        for chunk, off, n in self.segments(f):
            buf = bytearray(self.chunk_bytes(chunk))
            buf[off:off + n] = stream[cursor:cursor + n]
            cursor += n
            checksum = xxhash.xxh64_intdigest(buf[:-16])
            struct.pack_into('<Q', buf, len(buf) - 8, checksum)
            struct.pack_into('<Q', manifest, self.chunk_table + chunk['index'] * 32 + 24, checksum)
            (output / 'chunks' / chunk['name']).write_bytes(buf)
        struct.pack_into('<II', manifest, f['entry'] + 16, len(compressed), len(encrypted))
        manifest[f['entry'] + 32] = 1
        struct.pack_into('<Q', manifest, self.fhash + f['index'] * 8, xxhash.xxh64_intdigest(encrypted))
        (output / 'manifest.ssra').write_bytes(manifest)
        overrides = {p.name: p for p in (output / 'chunks').glob('*.ssrc')}
        verify = Archive(self.root, output / 'manifest.ssra', self.overrides | overrides)
        reread = Database(verify.read_file(f['name']), require_native_phase=True)
        if reread.texts != source.texts | translations:
            raise FormatError('Bản vá không vượt qua kiểm tra đọc lại.')
        return {'rows': source.rows, 'translated': len(translations), 'db_size': len(encrypted),
                'compressed_size': len(compressed), 'chunks': sorted(overrides)}

    def patch_story_file(self, filename, encrypted, output):
        """Patch the validated inline JP story table within its original slot."""
        story_chunk_map = {
            'db/story_main_part1new_260729@story.db': 'base_b21_0.ssrc',
            'db/story_sub_part1new_260729@story.db': 'base_b17_0.ssrc',
            'db/story_char_messenger_chat_260930@story.db': 'base_b22_0.ssrc',
            'db/story_visit_260930@story.db': 'base_b31_0.ssrc',
            'db/story_friendship_260930@story.db': 'base_b31_0.ssrc',
            'db/story_counseling_260930@story.db': 'base_b01_0.ssrc',
            # Nhóm 1: Tutorial
            'db/story_main_part1_251203@story.db': 'base_b13_0.ssrc',
            'db/story_main_part2_260708@story.db': 'base_b13_0.ssrc',
            'db/story_etc_260909@story.db': 'base_b12_0.ssrc',
            # Nhóm 4: Trauma Code
            'db/story_trauma_code_1004_251022@story.db': 'base_b06_0.ssrc',
            'db/story_trauma_code_1041_251224@story.db': 'base_b23_0.ssrc',
            'db/story_trauma_code_1052_260225@story.db': 'base_b12_0.ssrc',
            'db/story_trauma_code_1061_260408@story.db': 'base_b09_0.ssrc',
            'db/story_trauma_code_1062_260729@story.db': 'base_b19_0.ssrc',
            'db/story_trauma_code_30048_260708@story.db': 'base_b22_0.ssrc',
            # Nhóm 2: Main Story mở rộng
            'db/story_main_part3_260729@story.db': 'base_b14_0.ssrc',
            'db/story_main_part4_260930@story.db': 'base_b17_0.ssrc',
            'db/story_main_part5_260909@story.db': 'base_b02_0.ssrc',
            # Nhóm 3: Sub Story
            'db/story_sub_part1_260114@story.db': 'base_b04_0.ssrc',
            'db/story_sub_part2_260708@story.db': 'base_b14_0.ssrc',
            'db/story_sub_part3_260708@story.db': 'base_b13_0.ssrc',
            'db/story_sub_part4_260729@story.db': 'base_b29_0.ssrc',
            'db/story_sub_part5_260909@story.db': 'base_b02_0.ssrc',
            # Nhóm 5: Sự kiện & Ngoại truyện
            'db/story_counseling_memoryerase@story.db': 'base_b07_0.ssrc',
            'db/story_live_event_260930@story.db': 'base_b07_0.ssrc',
        }
        if filename not in story_chunk_map:
            raise FormatError('Bảng kịch bản chưa được hỗ trợ.')
        f = self.files[filename]
        if f['enc']:
            raise FormatError('Lớp mã hóa story chưa được hỗ trợ.')
        compressed = next((candidate for level in (9, 15, 19)
                           if len(candidate := zstd.ZstdCompressor(level=level, write_checksum=True).compress(encrypted)) <= f['cs']), None)
        if compressed is None:
            raise FormatError('Bản dịch cốt truyện vượt vùng chứa; chưa ghi game.')
        if zstd.ZstdDecompressor().decompress(compressed, allow_extra_data=False) != encrypted:
            raise FormatError('Story compression readback mismatch')
        output = Path(output)
        (output / 'chunks').mkdir(parents=True, exist_ok=True)
        manifest, cursor = bytearray(self.data), 0
        stream = compressed + bytes(f['cs'] - len(compressed))
        touched = []
        expected_chunk = story_chunk_map[filename]
        for chunk, off, size in self.segments(f):
            if chunk['name'] != expected_chunk:
                raise FormatError('Vị trí story đã đổi sau cập nhật; cần xác minh vùng chứa mới.')
            original = self.chunk_bytes(chunk)
            buf = bytearray(original)
            buf[off:off + size] = stream[cursor:cursor + size]
            cursor += size
            # Every byte outside the old story slot (except checksum footer)
            # must remain identical, including all other game resources.
            mv_buf, mv_orig = memoryview(buf), memoryview(original)
            if mv_buf[:off] != mv_orig[:off] or mv_buf[off + size:-8] != mv_orig[off + size:-8]:
                raise FormatError('Story patch changed unrelated resource bytes')
            checksum = xxhash.xxh64_intdigest(mv_buf[:-16])
            struct.pack_into('<Q', buf, len(buf) - 8, checksum)
            struct.pack_into('<Q', manifest, self.chunk_table + chunk['index'] * 32 + 24, checksum)
            (output / 'chunks' / chunk['name']).write_bytes(buf)
            touched.append(chunk['name'])
        struct.pack_into('<II', manifest, f['entry'] + 16, len(compressed), len(encrypted))
        manifest[f['entry'] + 32] = 1
        struct.pack_into('<Q', manifest, self.fhash + f['index'] * 8, xxhash.xxh64_intdigest(encrypted))
        (output / 'manifest.ssra').write_bytes(manifest)
        overrides = {p.name: p for p in (output / 'chunks').glob('*.ssrc')}
        check = Archive(self.root, output / 'manifest.ssra', self.overrides | overrides)
        if check.read_file(filename) != encrypted:
            raise FormatError('Story archive readback mismatch')
        return dict(file=filename, uncompressed_size=len(encrypted), compressed_size=len(compressed), chunks=touched,
                    unrelated_resource_bytes_identical=True)


TOKENS = re.compile(r'\{[^{}\r\n]+\}|<[^>\r\n]*>|\$[^$<>\r\n]+\$|%(?:\d+\$)?[sdif]|\\[nr]')
_TECH_TOKENS = re.compile(r'\{[^{}\r\n]+\}|<[^>\r\n]*>|%(?:\d+\$)?[sdif]|\\[nr]')
_DOLLAR_TOKENS = re.compile(r'(?<!<)\$[^$<>\r\n]+\$(?!>)')
_TOKEN_MAP = None


def _get_token_map():
    global _TOKEN_MAP
    if _TOKEN_MAP is None:
        _TOKEN_MAP = {}
        candidates = []
        if getattr(sys, 'frozen', False):
            if hasattr(sys, '_MEIPASS'):
                candidates.append(Path(sys._MEIPASS) / 'MAPPING_479_JP_TOKENS.json')
                candidates.append(Path(sys._MEIPASS) / 'data' / 'reports' / 'MAPPING_479_JP_TOKENS.json')
            exe_dir = Path(sys.executable).resolve().parent
            candidates.append(exe_dir / 'data' / 'reports' / 'MAPPING_479_JP_TOKENS.json')
            candidates.append(exe_dir / 'CZN_VietHoa_Project' / 'data' / 'reports' / 'MAPPING_479_JP_TOKENS.json')
        candidates.append(Path(__file__).resolve().parent.parent / 'data' / 'reports' / 'MAPPING_479_JP_TOKENS.json')
        candidates.append(Path.cwd() / 'data' / 'reports' / 'MAPPING_479_JP_TOKENS.json')
        candidates.append(Path.cwd() / 'CZN_VietHoa_Project' / 'data' / 'reports' / 'MAPPING_479_JP_TOKENS.json')
        candidates.append(Path('C:/ProgramData/Smilegate/Games/ChaosZeroNightmare/CZN_VietHoa_Project/data/reports/MAPPING_479_JP_TOKENS.json'))
        mapping_file = next((p for p in candidates if p.is_file()), None)
        if mapping_file:
            try:
                import json
                with mapping_file.open('r', encoding='utf-8') as f:
                    data = json.load(f)
                    for k, v in data.items():
                        if isinstance(v, dict) and v.get('vi'):
                            _TOKEN_MAP['$' + k + '$'] = '$' + v['vi'] + '$'
            except Exception:
                pass
    return _TOKEN_MAP


def tokens(text):
    from collections import Counter
    return Counter(TOKENS.findall(text))


def validate_translation(source, target):
    if not isinstance(target, str) or not target.strip():
        return 'Bản dịch trống'
    if '\0' in target:
        return 'Có ký tự NUL'
    if tokens(source) == tokens(target):
        return None

    from collections import Counter
    source_tech = Counter(_TECH_TOKENS.findall(source))
    target_tech = Counter(_TECH_TOKENS.findall(target))
    if source_tech != target_tech:
        return 'Thẻ hoặc biến khác bản gốc: ' + repr(dict(source_tech - target_tech)) + ' / ' + repr(dict(target_tech - source_tech))

    source_dollars = Counter(_DOLLAR_TOKENS.findall(source))
    target_dollars = Counter(_DOLLAR_TOKENS.findall(target))
    tmap = _get_token_map()
    expected_dollars = Counter(tmap.get(tok, tok) for tok in _DOLLAR_TOKENS.findall(source))
    if expected_dollars != target_dollars:
        return 'Thẻ hoặc biến khác bản gốc: ' + repr(dict(expected_dollars - target_dollars)) + ' / ' + repr(dict(target_dollars - expected_dollars))

    return None

