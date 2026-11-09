"""Crash-recoverable, bounded segmented event journal for offline observations.

Writes are append-only and fsynced before the index checkpoint is made durable.
No live aircraft command relies on this storage path.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import json
import os
import struct
import zlib

_HEADER = struct.Struct('<II')  # body length and CRC32
_MAX_RECORD = 8 * 1024 * 1024


@dataclass(frozen=True)
class JournalEntry:
    segment: int
    offset: int
    payload: bytes


class Journal:
    def __init__(self, root: Path, *, segment_bytes: int = 4 * 1024 * 1024,
                 maximum_segments: int = 16):
        if not 1024 <= segment_bytes <= 1024 * 1024 * 1024 or not 1 <= maximum_segments <= 10000:
            raise ValueError('invalid journal limits')
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True)
        self.segment_bytes = segment_bytes
        self.maximum_segments = maximum_segments
        self._index = self._recover()
        self._uncheckpointed = 0

    def _segments(self) -> list[Path]:
        return sorted(self.root.glob('segment-????????.bin'))

    def _recover(self) -> list[tuple[int, int, int]]:
        index = []
        for segment_path in self._segments():
            ident = int(segment_path.stem.split('-')[1])
            with segment_path.open('r+b') as stream:
                while True:
                    offset = stream.tell()
                    header = stream.read(_HEADER.size)
                    if not header:
                        break
                    if len(header) != _HEADER.size:
                        stream.truncate(offset)
                        break
                    size, crc = _HEADER.unpack(header)
                    if not 0 < size <= _MAX_RECORD or offset + size + _HEADER.size > self.segment_bytes:
                        stream.truncate(offset)
                        break
                    payload = stream.read(size)
                    if len(payload) != size or zlib.crc32(payload) != crc:
                        stream.truncate(offset)
                        break
                    index.append((ident, offset, size))
        self._checkpoint(index)
        return index

    def _checkpoint(self, index: list[tuple[int, int, int]]) -> None:
        # Rebuildable index; the segment is authoritative in a crash.
        manifest = {'format': 1, 'entries': index}
        pending = self.root / 'index.pending'
        with pending.open('w', encoding='utf-8') as out:
            json.dump(manifest, out, separators=(',', ':'))
            out.flush()
            os.fsync(out.fileno())
        os.replace(pending, self.root / 'index.json')

    def append(self, payload: bytes) -> JournalEntry:
        if not isinstance(payload, bytes) or not 0 < len(payload) <= min(_MAX_RECORD, self.segment_bytes - 8):
            raise ValueError('record size exceeds journal limits')
        segments = self._segments()
        ident = int(segments[-1].stem.split('-')[1]) if segments else 0
        path = self.root / f'segment-{ident:08d}.bin'
        if path.exists() and path.stat().st_size + _HEADER.size + len(payload) > self.segment_bytes:
            ident += 1
            path = self.root / f'segment-{ident:08d}.bin'
        if not path.exists() and len(segments) >= self.maximum_segments:
            raise OverflowError('journal retention limit reached; explicit export/prune required')
        with path.open('ab') as stream:
            offset = stream.tell()
            stream.write(_HEADER.pack(len(payload), zlib.crc32(payload)))
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        self._index.append((ident, offset, len(payload)))
        self._uncheckpointed += 1
        if self._uncheckpointed >= 128:
            self.close()
        return JournalEntry(ident, offset, payload)

    def read(self, index: int) -> JournalEntry:
        ident, offset, size = self._index[index]
        with (self.root / f'segment-{ident:08d}.bin').open('rb') as stream:
            stream.seek(offset)
            header = stream.read(_HEADER.size)
            data = stream.read(size)
        if len(header) != _HEADER.size or len(data) != size or _HEADER.unpack(header) != (size, zlib.crc32(data)):
            raise IOError('journal corruption detected')
        return JournalEntry(ident, offset, data)

    def close(self) -> None:
        """Persist the derived index; segments remain authoritative after a crash."""
        if self._uncheckpointed:
            self._checkpoint(self._index)
            self._uncheckpointed = 0

    def __enter__(self) -> 'Journal':
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def __len__(self) -> int:
        return len(self._index)
