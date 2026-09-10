import multiprocessing
import tempfile
import unittest
from pathlib import Path


def increment(directory):
    from app.config import settings
    settings.data_dir = directory
    from app.services.locking import process_lock
    lock = process_lock('test-counter')
    path = Path(directory) / 'counter.txt'
    for _ in range(30):
        with lock:
            value = int(path.read_text())
            path.write_text(str(value + 1))


class ProcessLockTest(unittest.TestCase):
    def test_four_processes_do_not_lose_updates(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'counter.txt'
            path.write_text('0')
            processes = [multiprocessing.get_context('spawn').Process(target=increment, args=(directory,)) for _ in range(4)]
            for process in processes: process.start()
            for process in processes:
                process.join(timeout=30)
                if process.is_alive():
                    process.terminate()
                    process.join()
                    self.fail('process lock timed out')
                self.assertEqual(process.exitcode, 0)
            self.assertEqual(path.read_text(), '120')
