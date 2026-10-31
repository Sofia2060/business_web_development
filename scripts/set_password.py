"""Set the password of an existing user (the sample accounts have fake hashes).

Usage: uv run python scripts/set_password.py admin@vinora.vn
"""
import getpass
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))

from dotenv import load_dotenv

load_dotenv()

from app.auth import MAX_PASSWORD_BYTES, hash_password
from app.db import query, transaction

email = sys.argv[1].strip().lower() if len(sys.argv) > 1 else sys.exit(__doc__)
if not query("SELECT 1 AS x FROM dbo.Users WHERE Email = ?", (email,)):
    sys.exit(f"No user with email {email}")
password = getpass.getpass("New password: ")
if password != getpass.getpass("Repeat password: "):
    sys.exit("The two passwords differ")
if len(password) < 8 or len(password.encode()) > MAX_PASSWORD_BYTES:
    sys.exit(f"Password must be 8 to {MAX_PASSWORD_BYTES} bytes")
with transaction() as cur:
    cur.execute("UPDATE dbo.Users SET PasswordHash = ?, UpdatedAt = SYSDATETIME() WHERE Email = ?",
                (hash_password(password), email))
print("Password updated.")
