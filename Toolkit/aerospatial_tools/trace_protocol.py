"""Validate Swift PipelineSpan JSONL and produce bounded causal summaries."""
from __future__ import annotations

from pathlib import Path
import json

from .tracing import TraceSpan, TraceStore


def inspect_trace(path: Path, *, capacity: int = 100_000) -> dict:
    store = TraceStore(capacity)
    with path.open('r', encoding='utf-8') as source:
        for number, line in enumerate(source, 1):
            if len(line.encode('utf-8')) > 8192:
                raise ValueError(f'oversized trace record at {number}')
            if not line.strip():
                continue
            item = json.loads(line)
            if type(item) is not dict or set(item) != {
                'traceId', 'spanId', 'parentId', 'clockDomain', 'startNs',
                'endNs', 'name', 'outcome'
            }:
                raise ValueError(f'invalid trace fields at {number}')
            store.add(TraceSpan(item['traceId'], item['spanId'], item['parentId'],
                                item['clockDomain'], item['startNs'], item['endNs'],
                                item['name'], item['outcome']))
    return store.report()
