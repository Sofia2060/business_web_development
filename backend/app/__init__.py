from dotenv import load_dotenv
from flask import Flask


def create_app() -> Flask:
    load_dotenv()  # read .env if present
    app = Flask(__name__)
    app.json.ensure_ascii = False  # keep Vietnamese text readable in JSON

    from .routes import products
    app.register_blueprint(products.bp)
    return app
