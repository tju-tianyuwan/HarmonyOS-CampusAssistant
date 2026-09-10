"""Local administrator CLI; bind credentials without replacing existing course data."""
import argparse
from getpass import getpass

from sqlmodel import Session, select

from app.db import engine, init_db
from app.models import Account, AuthSession, User
from app.routers.auth import Credentials, identity
from app.services.security import hash_password


def main():
    parser = argparse.ArgumentParser(description="List users or bind an existing school account locally")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--user-id", type=int)
    parser.add_argument("--school")
    parser.add_argument("--number")
    args = parser.parse_args()
    init_db()
    with Session(engine) as db:
        if args.list:
            for user in db.exec(select(User)).all():
                print(f"{user.id}\t{user.role}\t{user.name}")
            return
        if not args.user_id or not args.school or not args.number:
            parser.error("Supply --user-id, --school and --number, or --list")
        user = db.get(User, args.user_id)
        if not user:
            parser.error("User does not exist")
        password = getpass("New password (8-128 characters): ")
        if not 8 <= len(password) <= 128 or password != getpass("Confirm password: "):
            parser.error("Passwords must match and contain 8-128 characters")
        credentials = Credentials(account_type="school", school_name=args.school,
                                  student_number=args.number, password=password)
        key = identity(credentials)
        duplicate = db.exec(select(Account).where(Account.login_key == key)).first()
        if duplicate and duplicate.user_id != user.id:
            parser.error("Identity is already bound to another user")
        account = db.exec(select(Account).where(Account.user_id == user.id)).first()
        if account and account.account_type != "school":
            parser.error("Personal accounts cannot be converted by this command")
        account = account or Account(user_id=user.id, login_key=key, password_hash="", account_type="school")
        account.login_key = key
        account.school_name = args.school.strip()
        account.student_number = args.number.strip()
        account.password_hash = hash_password(password)
        account.verification_status = "verified"
        db.add(account)
        for session in db.exec(select(AuthSession).where(AuthSession.user_id == user.id)).all():
            db.delete(session)
        db.commit()
        print(f"Bound credentials for user {user.id}; existing sessions revoked.")


if __name__ == "__main__":
    main()
