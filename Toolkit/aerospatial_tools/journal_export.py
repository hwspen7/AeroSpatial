"""Export validated application journal segments to portable JSON Lines.

The on-device writer persists CRC-framed records; this tool verifies them and
creates an explicit export without silently overwriting any existing data.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
from .journal import Journal


def export_journal(source: Path, destination: Path) -> int:
    source, destination = Path(source), Path(destination)
    if not source.is_dir() or not destination.parent.is_dir():
        raise ValueError('journal input or export directory does not exist')
    count = 0
    with Journal(source) as journal:
        try:
            with destination.open('x', encoding='utf-8', newline='\n') as output:
                for number in range(len(journal._index)):
                    entry = journal.read(number)
                    if len(entry.payload) > 65536:
                        raise ValueError('journal record exceeds permitted export length')
                    try:
                        data = json.loads(entry.payload)
                    except (ValueError, UnicodeDecodeError) as error:
                        raise ValueError('journal contains non-JSON records') from error
                    if not isinstance(data, dict) or data.get('schemaVersion') != 1:
                        raise ValueError('journal contains unsupported record format')
                    output.write(json.dumps(data, ensure_ascii=False, separators=(',', ':')) + '\n')
                    count += 1
                output.flush()
                os.fsync(output.fileno())
        except BaseException:
            destination.unlink(missing_ok=True)
            raise
    return count
