import os

import pyodbc
from dotenv import load_dotenv
from flask import Flask, jsonify

from .db import ProcError

# HTTP status for each error number thrown by the stored procedures and triggers (see database/*.sql).
# Anything not listed is treated as a bad request (400).
PROC_ERROR_STATUS = {
    50001: 409, 50002: 409,              # order trigger: locked order, wrong status step
    50013: 409, 50014: 409, 50015: 409,  # item discontinued, no price, not enough stock
    50017: 404, 50020: 409, 50021: 404, 50022: 409,
    50024: 403, 50025: 404, 50026: 409,
    50028: 409,                          # order is already in the requested status
    50038: 409,                          # online order is not paid yet, cannot be confirmed
    50041: 409, 50043: 409,              # payment: transaction id already used, amount does not match
    50048: 409,                          # checkout token belongs to another customer
    50029: 403,                          # order is above 5,000,000 VND: cancel by phone, not on the website
}


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

    @app.errorhandler(ProcError)
    def handle_proc_error(error: ProcError):
        return jsonify(error=error.message, code=error.code), PROC_ERROR_STATUS.get(error.code, 400)

    @app.errorhandler(pyodbc.IntegrityError)
    def handle_conflict(error):
        # A database rule was broken, usually because two requests ran at the same moment
        # (duplicate cart line, a voucher that just ran out). The caller can simply try again.
        return jsonify(error="The request conflicts with the current data. Please try again."), 409

    @app.errorhandler(pyodbc.Error)
    def handle_database_error(error):
        # Do not leak SQL text to the client. A deadlock or a lock timeout also ends up here.
        app.logger.exception("Database error")
        return jsonify(error="Database error. Please try again."), 500

    from .routes import addresses, admin, auth, cart, orders, products
    for module in (products, auth, admin, addresses, cart, orders):
        app.register_blueprint(module.bp)
    return app
