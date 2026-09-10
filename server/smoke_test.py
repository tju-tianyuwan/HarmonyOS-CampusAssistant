"""Run isolated workflow tests, with optional authenticated read-only live checks."""
import argparse
import os
from pathlib import Path
import unittest

import httpx


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", help="Optional live server URL, e.g. http://127.0.0.1:8000")
    args = parser.parse_args()
    suite = unittest.defaultTestLoader.discover(str(Path(__file__).parent / "tests"))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        raise SystemExit(1)
    if args.base_url:
        base = args.base_url.rstrip("/")
        with httpx.Client(timeout=15) as client:
            client.get(base + "/health").raise_for_status()
            assert client.get(base + "/api/v1/auth/users").status_code == 401
            token = os.getenv("SMOKE_TOKEN", "")
            if token:
                client.headers["Authorization"] = "Bearer " + token
                response = client.get(base + "/api/v1/auth/me")
                response.raise_for_status()
                user = response.json()
                client.get(base + f"/api/v1/courses?user_id={user['id']}").raise_for_status()
        print("Live read-only checks passed.")


if __name__ == "__main__":
    main()
