"""Strict PLPcK table access for inline story localization, with no script edits."""
import json
import struct
from czn_format import KEY, Record, FormatError, xor_bytes, u40, put40


class StoryTable:
    def __init__(self, encrypted):
        phase = len(encrypted) % 256
        self.phase = phase
        self.data = xor_bytes(encrypted, KEY[phase:] + KEY[:phase])
        d = self.data
        if len(d) < 38 or d[:8] != b'PLPcK\x01&\x00':
            raise FormatError('Unsupported native story table')
        self.count, self.buckets = struct.unpack_from('<II', d, 17)
        self.ht = u40(d, 25)
        if self.buckets > 2000000 or self.ht + 5 + self.buckets * 5 > len(d):
            raise FormatError('Invalid story hash table')
        if struct.unpack_from('<IB', d, self.ht) != (5 * (self.buckets + 1), 1):
            raise FormatError('Invalid root record')
        self.records, self.bucket_heads, visited = {}, [], set()
        for bucket in range(self.buckets):
            pos = u40(d, self.ht + 5 + bucket * 5)
            self.bucket_heads.append(pos)
            while pos:
                if pos in visited or pos + 15 > len(d):
                    raise FormatError('Invalid story record chain')
                visited.add(pos)
                size, kind, name_len, value_len = struct.unpack_from('<IBBI', d, pos)
                nxt = u40(d, pos + 10)
                if kind != 2 or size != 15 + name_len + value_len or pos + size > len(d):
                    raise FormatError('Invalid story record')
                name = d[pos + 15:pos + 15 + name_len].decode('utf-8')
                if name in self.records:
                    raise FormatError('Duplicate story key')
                self.records[name] = Record(pos, size, kind, name, nxt, d[pos + 15 + name_len:pos + size])
                pos = nxt
        # Structured DBs use a zero count sentinel; text DBs use a count.
        if self.count not in (0, len(self.records)):
            raise FormatError('Story record count mismatch')
        self.rows = struct.unpack('<I', self.records['\trows'].value)[0]
        cols = struct.unpack('<I', self.records['\tcols'].value)[0]
        self.columns = [self.records['\t' + str(i)].value.decode('utf-8') for i in range(cols)]
        if self.count == 0 and len(self.records) != 2 * self.rows + cols + 2:
            raise FormatError('Story zero-count table metadata mismatch')
        self.order, self.values = [], {}
        for i in range(self.rows):
            key = self.records['\t\t' + str(i)].value.decode('utf-8')
            parts = self.records[key].value.split(b'\0')
            if len(parts) != cols + 1 or parts[-1] or parts[0].decode('utf-8') != key:
                raise FormatError('Invalid story row: ' + key)
            self.order.append(key)
            self.values[key] = [part.decode('utf-8') for part in parts[:-1]]

    def rebuild(self, changed_values):
        if set(changed_values) - self.values.keys():
            raise FormatError('Unknown story row')
        ordered = sorted(self.records.values(), key=lambda r: r.offset)
        prefix = min(r.offset for r in ordered)
        if prefix < self.ht + 5 + self.buckets * 5:
            raise FormatError('Overlapping story record')
        result, relocated, pending = bytearray(self.data[:prefix]), {}, []
        for record in ordered:
            name, value = record.name.encode('utf-8'), record.value
            if record.name in changed_values:
                values = changed_values[record.name]
                if len(values) != len(self.columns) or values[0] != record.name or any('\0' in v for v in values):
                    raise FormatError('Invalid rebuilt story values')
                value = b'\0'.join(v.encode('utf-8') for v in values) + b'\0'
            pos = len(result)
            relocated[record.offset] = pos
            result += struct.pack('<IBBI', 15 + len(name) + len(value), record.kind, len(name), len(value))
            result += bytes(5) + name + value
            pending.append((pos + 10, record.next))
        for pos, old in pending:
            put40(result, pos, relocated[old] if old else 0)
        for bucket, old in enumerate(self.bucket_heads):
            put40(result, self.ht + 5 + bucket * 5, relocated[old] if old else 0)
        phase = len(result) % 256
        output = xor_bytes(bytes(result), KEY[phase:] + KEY[:phase])
        check = StoryTable(output)
        if check.order != self.order or check.columns != self.columns or check.values != self.values | changed_values:
            raise FormatError('Story native readback mismatch')
        return output

    def scene(self, key):
        return json.loads(self.values[key][self.columns.index('info')])
