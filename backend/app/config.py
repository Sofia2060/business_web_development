"""Settings read from environment variables (see .env.example)."""
import os
from pathlib import Path

# The web pages. Flask serves this folder, so pages and API share one address.
FRONTEND_DIR = Path(__file__).resolve().parents[2] / "frontend"


def db_connection_string() -> str:
    """Build the ODBC connection string for SQL Server.

    Without DB_USER the connection uses Windows Authentication.
    """
    parts = [
        "DRIVER={ODBC Driver 18 for SQL Server}",
        f"SERVER={os.getenv('DB_SERVER', 'localhost')}",
        f"DATABASE={os.getenv('DB_NAME', 'VinoraJewelry')}",
        "TrustServerCertificate=yes",
    ]
    user = os.getenv("DB_USER")
    if user:
        parts += [f"UID={user}", f"PWD={os.getenv('DB_PASSWORD', '')}"]
    else:
        parts.append("Trusted_Connection=yes")
    return ";".join(parts)


# Shipping rule, copied from frontend/mock-data/config.json ("giaoHang"):
# standard delivery costs 30,000 VND and is free for orders of 2,000,000 VND or more.
STANDARD_SHIPPING_FEE = 30_000
FREE_SHIPPING_FROM = 2_000_000
