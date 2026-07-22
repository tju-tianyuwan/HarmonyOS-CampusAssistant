from sqlalchemy import text
from sqlmodel import SQLModel, Session, create_engine

from .config import settings

connect_args = {"check_same_thread": False} if settings.database_url.startswith("sqlite") else {}
engine = create_engine(settings.database_url, connect_args=connect_args)


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
