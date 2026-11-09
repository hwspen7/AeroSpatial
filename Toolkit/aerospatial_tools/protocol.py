"""Strict version-aware transport envelope migration with explicit compatibility.

V2 adds typed provenance counters and optional normalized timestamp uncertainty.
No implicit conversion of clock domains occurs in this module.
"""
from __future__ import annotations
from dataclasses import dataclass
import json

FIELDS = {'version', 'stream', 'timestampNs', 'clockDomain', 'sequence', 'traceId',
          'kind', 'quality', 'payloadBytes', 'missed', 'upstreamMissing',
          'sampled', 'rejected', 'alignedNs', 'uncertaintyNs'}
UINT64 = (1 << 64) - 1


class ProtocolError(ValueError):
    pass


def _uint(name: str, value: object, *, positive: bool = False) -> int:
    if type(value) is not int or not int(positive) <= value <= UINT64:
        raise ProtocolError(f'{name} must be a bounded unsigned integer')
    return value


@dataclass(frozen=True)
class TransportPacket:
    stream: int
    timestamp_ns: int
    sequence: int
    clock_domain: int
    kind: int
    trace_id: int
    quality: int
    payload_bytes: int
    missed: int = 0
    upstream_missing: int = 0
    sampled: int = 0
    rejected: int = 0
    aligned_ns: int | None = None
    uncertainty_ns: int | None = None

    @classmethod
    def from_dict(cls, obj: dict) -> 'TransportPacket':
        if not isinstance(obj, dict) or set(obj) - FIELDS:
            raise ProtocolError('unknown fields or invalid object')
        version = obj.get('version', 1)
        if type(version) is not int or version not in (1, 2):
            raise ProtocolError('unsupported protocol version')
        if version == 1 and any(key in obj for key in ('upstreamMissing', 'sampled', 'rejected', 'alignedNs', 'uncertaintyNs')):
            raise ProtocolError('v2-only field in older envelope')
        args = {name: _uint(key, obj.get(key, 0), positive=key in ('stream', 'sequence', 'clockDomain'))
                for name, key in (('stream', 'stream'), ('timestamp_ns', 'timestampNs'),
                                  ('sequence', 'sequence'), ('clock_domain', 'clockDomain'),
                                  ('kind', 'kind'), ('trace_id', 'traceId'),
                                  ('quality', 'quality'), ('payload_bytes', 'payloadBytes'),
                                  ('missed', 'missed'), ('upstream_missing', 'upstreamMissing'),
                                  ('sampled', 'sampled'), ('rejected', 'rejected'))}
        if args['stream'] > 5 or not args['quality'] & 1 or args['quality'] & ~63:
            raise ProtocolError('invalid stream or quality')
        if args['payload_bytes'] > 8 * 1024 * 1024:
            raise ProtocolError('oversized event')
        aligned = obj.get('alignedNs')
        uncertainty = obj.get('uncertaintyNs')
        if (aligned is None) != (uncertainty is None):
            raise ProtocolError('aligned time requires uncertainty')
        return cls(**args, aligned_ns=_uint('alignedNs', aligned) if aligned is not None else None,
                   uncertainty_ns=_uint('uncertaintyNs', uncertainty) if uncertainty is not None else None)

    def as_dict(self, *, version: int = 2) -> dict:
        if version not in (1, 2):
            raise ProtocolError('unsupported target version')
        obj = {'version': version, 'stream': self.stream, 'timestampNs': self.timestamp_ns,
               'clockDomain': self.clock_domain, 'sequence': self.sequence, 'traceId': self.trace_id,
               'kind': self.kind, 'quality': self.quality, 'payloadBytes': self.payload_bytes,
               'missed': self.missed}
        if version == 1:
            if self.upstream_missing or self.sampled or self.rejected or self.aligned_ns is not None:
                raise ProtocolError('downgrade would lose provenance or alignment')
        else:
            obj.update(upstreamMissing=self.upstream_missing, sampled=self.sampled,
                       rejected=self.rejected)
            if self.aligned_ns is not None:
                obj.update(alignedNs=self.aligned_ns, uncertaintyNs=self.uncertainty_ns)
        return obj

    def encoded(self) -> bytes:
        return (json.dumps(self.as_dict(), separators=(',', ':'), sort_keys=True) + '\n').encode()
