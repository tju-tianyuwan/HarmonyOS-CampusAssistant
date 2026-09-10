"""Same-host process locks, also released by the OS after a worker crash."""
import asyncio
import hashlib
from contextlib import asynccontextmanager
from pathlib import Path

from filelock import FileLock, Timeout
from ..config import settings


def process_lock(name: str) -> FileLock:
    directory = Path(settings.data_dir).resolve() / "locks"
    directory.mkdir(parents=True, exist_ok=True)
    key = hashlib.sha256((settings.database_url + ":" + name).encode()).hexdigest()
    return FileLock(directory / (key + ".lock"))


@asynccontextmanager
async def async_process_lock(name: str):
    lock = process_lock(name)
    while True:
        try:
            lock.acquire(timeout=0)
            break
        except Timeout:
            await asyncio.sleep(0.05)
    try:
        yield
    finally:
        lock.release()
