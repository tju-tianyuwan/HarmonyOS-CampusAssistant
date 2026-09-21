from sqlalchemy import text
from sqlalchemy import event
from sqlmodel import SQLModel, Session, create_engine

from .config import settings
from .services.locking import process_lock

connect_args = {"check_same_thread": False, "timeout": 30} if settings.database_url.startswith("sqlite") else {}
engine = create_engine(settings.database_url, connect_args=connect_args)
write_lock = process_lock("database-write")

if settings.database_url.startswith("sqlite"):
    @event.listens_for(engine, "connect")
    def configure_sqlite(connection, _):
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute("PRAGMA busy_timeout=30000")


def init_db() -> None:
    SQLModel.metadata.create_all(engine)
    if settings.database_url.startswith("sqlite"):
        with engine.begin() as conn:
            cols = [row[1] for row in conn.execute(text("PRAGMA table_info(outline)")).fetchall()]
            if "owner_id" not in cols:
                conn.execute(text("ALTER TABLE outline ADD COLUMN owner_id INTEGER DEFAULT -1"))
            session_cols = [row[1] for row in conn.execute(text("PRAGMA table_info(coursesession)")).fetchall()]
            if session_cols and "ai_title" not in session_cols:
                conn.execute(text("ALTER TABLE coursesession ADD COLUMN ai_title VARCHAR DEFAULT ''"))
            note_cols = [row[1] for row in conn.execute(text("PRAGMA table_info(note)")).fetchall()]
            if note_cols and "session_id" not in note_cols:
                conn.execute(text("ALTER TABLE note ADD COLUMN session_id INTEGER"))
                conn.execute(text("CREATE INDEX IF NOT EXISTS ix_note_session_id ON note (session_id)"))
            meeting_cols = [row[1] for row in conn.execute(text("PRAGMA table_info(meetingroom)")).fetchall()]
            if meeting_cols and "room_type" not in meeting_cols:
                conn.execute(text(
                    "ALTER TABLE meetingroom ADD COLUMN room_type VARCHAR DEFAULT 'ai_meeting'"
                ))
            if meeting_cols and "agent_mode" not in meeting_cols:
                conn.execute(text("ALTER TABLE meetingroom ADD COLUMN agent_mode VARCHAR DEFAULT 'multi'"))
            if meeting_cols:
                conn.execute(text(
                    "UPDATE meetingroom SET room_type = 'ai_meeting', agent_mode = 'single', enabled = 1 "
                    "WHERE room_type = 'group_chat'"
                ))


def get_db():
    with Session(engine) as db:
        yield db
