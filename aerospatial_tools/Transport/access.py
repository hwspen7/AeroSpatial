"""Default-deny purpose-specific export policy for offline metadata.

This application-level policy is NOT encryption or an OS access-control boundary.
"""
from __future__ import annotations

from dataclasses import dataclass

_VALID = frozenset({'head', 'telemetry', 'video', 'perception', 'diagnostic'})
_PURPOSES = frozenset({'analysis', 'share', 'research'})


@dataclass(frozen=True)
class Grant:
    purpose: str
    streams: frozenset[str]
    expires_ns: int

    def __post_init__(self):
        if (self.purpose not in _PURPOSES or not self.streams or
            not self.streams <= _VALID or type(self.expires_ns) is not int or
            not 0 < self.expires_ns <= (1 << 64) - 1):
            raise ValueError('invalid data access grant')


class AccessPolicy:
    def __init__(self, grants: tuple[Grant, ...] = ()) -> None:
        self.grants = tuple(grants)
        if any(not isinstance(grant, Grant) for grant in self.grants):
            raise ValueError('invalid grants')

    def permits(self, purpose: str, stream: str, now_ns: int) -> bool:
        if purpose not in _PURPOSES or stream not in _VALID or (
            type(now_ns) is not int or not 0 <= now_ns <= (1 << 64) - 1
        ):
            return False
        return any(grant.purpose == purpose and stream in grant.streams and
                   now_ns < grant.expires_ns for grant in self.grants)
