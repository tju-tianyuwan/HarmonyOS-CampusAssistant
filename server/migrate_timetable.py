"""Back up the project SQLite database and add only the timetable tables."""

import json
import sqlite3
from contextlib import closing
from datetime import datetime
from pathlib import Path

from sqlalchemy.engine import make_url

from app.config import settings
from app.db import engine, write_lock
from app.models import CourseSchedule, TimetableEntry, TimetableSettings


def migrate(backup_dir: Path | None = None):
    project = Path(__file__).resolve().parent.parent
    url = make_url(settings.database_url)
    if url.get_backend_name() != "sqlite" or not url.database:
        raise RuntimeError("This migration supports project-local SQLite files only")
    database = Path(url.database).resolve(strict=True)
    if not database.is_relative_to(project):
        raise RuntimeError("Database must be inside the current project")
    folder = backup_dir if backup_dir is not None else project / ".codex-run" / "backups"
    if not folder.resolve().is_relative_to(project):
        raise RuntimeError("Backup directory must be inside the current project")
    folder.mkdir(parents=True, exist_ok=True)
    backup = folder / f"smartstudy-before-timetable-{datetime.now():%Y%m%d-%H%M%S-%f}.db"
    tables = [TimetableSettings.__table__, TimetableEntry.__table__, CourseSchedule.__table__]

    with write_lock:
        with closing(sqlite3.connect(database.as_uri() + "?mode=ro", uri=True)) as source:
            if source.execute("PRAGMA quick_check").fetchall() != [("ok",)]:
                raise RuntimeError("Database integrity check failed; no migration applied")
            with closing(sqlite3.connect(backup)) as target:
                source.backup(target)
                if target.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
                    raise RuntimeError("Backup verification failed; no migration applied")
        print(f"Verified backup: {backup}", flush=True)
        with engine.begin() as connection:
            for table in tables:
                table.create(connection, checkfirst=True)
        with closing(sqlite3.connect(database.as_uri() + "?mode=ro", uri=True)) as current:
            current.execute("ATTACH DATABASE ? AS previous", (str(backup),))
            # Compare original records, not just counts, without exposing user data.
            names = current.execute(
                "SELECT name FROM previous.sqlite_master WHERE type = 'table'"
            ).fetchall()
            for (name,) in names:
                quoted = '"' + name.replace('"', '""') + '"'
                before = current.execute(f"SELECT * FROM previous.{quoted}").fetchall()
                after = current.execute(f"SELECT * FROM main.{quoted}").fetchall()
                if sorted(before, key=repr) != sorted(after, key=repr):
                    raise RuntimeError(f"Existing records changed in {name}; inspect backup")
            result = {
                "database": str(database), "backup": str(backup),
                "preserved_tables": len(names),
                "timetable_rows": {table.name: current.execute(
                    f'SELECT COUNT(*) FROM "{table.name}"'
                ).fetchone()[0] for table in tables},
                "integrity": current.execute("PRAGMA integrity_check").fetchone()[0],
            }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return result


if __name__ == "__main__":
    migrate()
