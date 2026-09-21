import io
import sqlite3
import tempfile
import threading
import unittest
from contextlib import closing, redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from sqlmodel import create_engine

import migrate_timetable


class ScheduleMigrationTest(unittest.TestCase):
    def test_backup_preservation_and_repeatability(self):
        project = Path(__file__).resolve().parents[2]
        scratch = project / '.codex-run'
        scratch.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='schedule-migration-test-', dir=scratch) as folder:
            root = Path(folder)
            database = root / 'test.db'
            with closing(sqlite3.connect(database)) as db:
                db.execute('PRAGMA journal_mode=WAL')
                db.execute('CREATE TABLE user (id INTEGER PRIMARY KEY, name TEXT)')
                db.execute('CREATE TABLE classcourse (id INTEGER PRIMARY KEY, name TEXT)')
                db.execute("INSERT INTO user VALUES (1, 'Original student')")
                db.execute("INSERT INTO classcourse VALUES (1, 'Original course')")
                db.commit()
                engine = create_engine('sqlite:///' + database.as_posix())
                try:
                    with patch.object(migrate_timetable, 'engine', engine), \
                            patch.object(migrate_timetable, 'settings', SimpleNamespace(database_url=str(engine.url))), \
                            patch.object(migrate_timetable, 'write_lock', threading.RLock()), redirect_stdout(io.StringIO()):
                        first = migrate_timetable.migrate(root / 'backups')
                        second = migrate_timetable.migrate(root / 'backups')
                    self.assertEqual(first['integrity'], 'ok')
                    self.assertEqual(second['integrity'], 'ok')
                    self.assertEqual(second['timetable_rows']['courseschedule'], 0)
                    self.assertNotEqual(first['backup'], second['backup'])
                    with closing(sqlite3.connect(first['backup'])) as backup:
                        self.assertEqual(backup.execute('SELECT name FROM user').fetchone()[0], 'Original student')
                        self.assertIsNone(backup.execute("SELECT name FROM sqlite_master WHERE name='courseschedule'").fetchone())
                    self.assertEqual(db.execute('SELECT name FROM classcourse').fetchone()[0], 'Original course')
                finally:
                    engine.dispose()


if __name__ == '__main__':
    unittest.main()
