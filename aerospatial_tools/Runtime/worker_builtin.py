"""Small reference functions used to verify isolated execution semantics."""
from __future__ import annotations


def summarize(event: dict) -> dict:
    values = event.get('values', [])
    if type(values) is not list or len(values) > 4096 or any(type(v) not in (int, float) for v in values):
        raise ValueError('invalid sample list')
    return {'summarize.count': len(values), 'summarize.sum': sum(values)}


def fail(_event: dict) -> dict:
    raise RuntimeError('intentional test failure')


def sleep(_event: dict) -> dict:
    import time
    time.sleep(5)
    return {'sleep.done': True}


def huge(_event: dict) -> dict:
    return {'huge.huge': 'x' * 200_000}
