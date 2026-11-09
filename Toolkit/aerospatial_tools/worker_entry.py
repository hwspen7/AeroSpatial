"""Trusted algorithm process entry. This is process isolation, not a security sandbox."""
from __future__ import annotations
import importlib
import os
import json
import sys


def main() -> None:
    # Apply limits before importing a trusted extension. Limits are inherited by
    # its descendants on POSIX, but this is not a security confinement boundary.
    if os.name == 'posix':
        import resource
        memory = int(os.environ.get('AEROSPATIAL_WORKER_ADDRESS_SPACE', '0'))
        output = int(os.environ.get('AEROSPATIAL_WORKER_OUTPUT_BYTES', '0'))
        if memory:
            resource.setrlimit(resource.RLIMIT_AS, (memory, memory))
        if output:
            resource.setrlimit(resource.RLIMIT_FSIZE, (output, output))
    payload = sys.stdin.buffer.read(8 * 1024 * 1024 + 4097)
    if len(payload) > 8 * 1024 * 1024 + 4096:
        raise ValueError('worker request too large')
    request = json.loads(payload)
    if type(request) is not dict or set(request) != {'entry', 'event'}:
        raise ValueError('invalid worker request')
    entry = request['entry']
    if type(entry) is not str or ':' not in entry:
        raise ValueError('invalid worker identifier')
    module, name = entry.split(':', 1)
    function = getattr(importlib.import_module(module), name)
    result = function(request['event'])
    if type(result) is not dict:
        raise ValueError('algorithm must return an object')
    sys.stdout.write(json.dumps(result, allow_nan=False, separators=(',', ':')))


if __name__ == '__main__':
    main()
