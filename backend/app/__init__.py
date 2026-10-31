import os

from dotenv import load_dotenv
from flask import Flask


def create_app() -> Flask:
    load_dotenv()  # read .env if present
    app = Flask(__name__)
    app.json.ensure_ascii = False  # keep Vietnamese text readable in JSON

    # Signs the login cookie. Without it anyone could forge a login.
    app.secret_key = os.getenv("SECRET_KEY")
    if not app.secret_key or len(app.secret_key) < 32:
        raise RuntimeError("SECRET_KEY is missing or shorter than 32 characters. Copy .env.example to .env and set a random value.")
    app.config["SESSION_COOKIE_SAMESITE"] = "Lax"  # blocks the cookie on cross-site POSTs
    app.config["MAX_CONTENT_LENGTH"] = 16 * 1024  # reject huge request bodies

    from .routes import admin, auth, products
    for module in (products, auth, admin):
        app.register_blueprint(module.bp)
    return app
