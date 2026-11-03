"""The account and cart code of the shop pages (frontend/src/js/core/session.js) must not turn a logged-in customer into
a visitor when the server cannot be reached for a moment, and must not send products that are no longer on sale.
Node runs the code against a scripted fake server (backend/tests/js/session.js); no browser, no database.
Skipped when Node is not installed."""
import json
import shutil
import subprocess
from pathlib import Path

import pytest

from app.config import FRONTEND_DIR

NODE = shutil.which("node")
HARNESS = Path(__file__).parent / "js" / "session.js"
CORE = FRONTEND_DIR / "src" / "js" / "core"

pytestmark = pytest.mark.skipif(NODE is None, reason="Node is not installed")


@pytest.fixture(scope="module")
def out():
    run = subprocess.run([NODE, str(HARNESS), str(CORE / "api.js"), str(CORE / "session.js")],
                         capture_output=True, text=True, encoding="utf-8", timeout=60)
    assert run.returncode == 0, run.stderr
    return json.loads(run.stdout)


def test_the_page_loads_as_a_visitor_when_the_server_says_not_logged_in(out):
    assert out["loadedAsVisitor"] == {"me": None, "khongRo": False, "notices": 0}


def test_a_network_error_is_not_a_visitor(out):
    assert out["networkDown"]["ok"] is False and out["networkDown"]["status"] == 0
    assert out["networkDownFlags"] == {"me": None, "khongRo": True, "matKetNoi": True}
    assert out["pageStaysWhenUnknown"] is True                   # a customer is not sent to the login page by a blip


def test_the_cart_is_not_changed_while_the_account_is_unknown(out):
    refused = out["addWhileDown"]
    assert refused["ok"] is False and refused["status"] == 0 and "Chưa kết nối được máy chủ" in refused["message"]
    assert out["localCartAfterRefusal"] == 0                     # nothing was written to this browser


def test_the_next_change_after_the_server_is_back_goes_to_the_account(out):
    assert out["addAfterRecovery"]["ok"] is True
    assert out["afterRecovery"] == {"me": "a@example.test", "serverCart": [2], "localCart": 0, "matKetNoi": False}


def test_a_401_is_a_visitor_and_goes_to_the_login_page(out):
    assert out["visitor"] == {"me": None, "khongRo": False}
    assert out["visitorGoesToLogin"] is True


def test_login_that_cannot_load_the_account_says_so(out):
    failed = out["loginThenDown"]
    assert failed["ok"] is False and "Đã đăng nhập" in failed["message"] and "tải lại trang" in failed["message"]


def test_a_saved_booking_or_cancellation_is_not_reported_as_failed_when_the_reload_fails(out):
    assert out["bookedWhileListDown"] == {"ok": True, "id": 11, "listed": [11]}
    assert out["cancelledWhileListDown"] == {"ok": True, "status": ["Cancelled"]}


def test_logging_out_empties_the_cards_and_appointments(out):
    assert out["afterLogout"] == {"cards": 0, "services": 0}


def test_products_not_on_sale_are_left_out_of_what_a_visitor_sends(out):
    assert out["sentToServer"] == ["SP1-V"]
    assert out["notOnSale"] == ["STOP", "QUOTE"]
    assert out["detailLines"] == ["SP1"]
