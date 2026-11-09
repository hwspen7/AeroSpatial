"""Recovery and conversion tests for app-native segmented recordings."""
from pathlib import Path
from tempfile import TemporaryDirectory
import json
import unittest
from aerospatial_tools.journal import Journal
from aerospatial_tools.journal_export import export_journal


class JournalExportTests(unittest.TestCase):
    def test_export_valid_records_and_no_overwrite(self):
        with TemporaryDirectory() as root:
            source = Path(root) / 'capture'
            destination = Path(root) / 'flight.jsonl'
            with Journal(source, segment_bytes=2048) as journal:
                for index in range(8):
                    journal.append(json.dumps({'schemaVersion': 1,
                        'sequence': index, 'kind': 'head'}).encode())
            self.assertEqual(export_journal(source, destination), 8)
            self.assertEqual(len(destination.read_text().splitlines()), 8)
            with self.assertRaises(FileExistsError):
                export_journal(source, destination)

    def test_refuses_non_json_or_unknown_schema(self):
        with TemporaryDirectory() as root:
            source = Path(root) / 'capture'
            destination = Path(root) / 'flight.jsonl'
            with Journal(source) as journal:
                journal.append(b'not-json')
            with self.assertRaises(ValueError):
                export_journal(source, destination)
            self.assertFalse(destination.exists())
