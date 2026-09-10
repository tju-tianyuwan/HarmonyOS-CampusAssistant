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


def get_db():
    with Session(engine) as db:
        yield db
