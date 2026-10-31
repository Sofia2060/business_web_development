"""Settings read from environment variables (see .env.example)."""
import os


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
