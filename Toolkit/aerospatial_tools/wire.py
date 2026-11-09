"""Portable head-motion wire codec matching the allocation-free C++ codec."""
from __future__ import annotations
import math
import struct
import zlib

_STRUCT = struct.Struct('<4sB3xQdddI')
MAX_UPTIME = ((1 << 64) - 1) / 1e9


def encode_head(uptime: float, yaw: float, pitch: float, roll: float) -> bytes:
    if any(type(x) not in (int, float) or not math.isfinite(x)
           for x in (uptime, yaw, pitch, roll)) or not 0 <= uptime < MAX_UPTIME:
        raise ValueError('invalid head-motion record')
    prefix = _STRUCT.pack(b'ASHD', 1, int(uptime * 1e9), yaw, pitch, roll, 0)[:-4]
    return prefix + struct.pack('<I', zlib.crc32(prefix))


def decode_head(payload: bytes) -> tuple[float, float, float, float]:
    if not isinstance(payload, bytes) or len(payload) != _STRUCT.size:
        raise ValueError('invalid head-motion payload length')
    magic, version, time_ns, yaw, pitch, roll, check = _STRUCT.unpack(payload)
    if magic != b'ASHD' or version != 1 or zlib.crc32(payload[:-4]) != check:
        raise ValueError('head-motion payload checksum or version mismatch')
    if not all(math.isfinite(x) for x in (yaw, pitch, roll)):
        raise ValueError('invalid head-motion orientation')
    return time_ns / 1e9, yaw, pitch, roll
