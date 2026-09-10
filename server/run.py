"""Supported same-host multiworker launcher; each worker shares DB, files and locks."""
import argparse
import os
import uvicorn

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--workers", type=int, default=1)
    args = parser.parse_args()
    if args.workers < 1: parser.error("workers must be positive")
    os.environ["CAMPUS_WORKERS"] = str(args.workers)
    uvicorn.run("app.main:app", host=args.host, port=args.port, workers=args.workers)
