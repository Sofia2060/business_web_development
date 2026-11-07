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


def test_a_visitors_history_stays_in_the_browser_and_joins_the_account_at_login(out):
    assert out["visitorViewed"] == {"list": ["B", "A"], "server": []}           # nothing is sent for a visitor
    # the browser's list goes up oldest first, the account's own entry stays, and the browser forgets its copy
    assert out["viewedMerged"] == {"server": ["X", "A", "B"], "list": ["B", "A", "X"], "local": 0}


def test_a_customers_history_changes_at_once_and_reaches_the_server_in_the_background(out):
    assert out["viewedAtOnce"] == ["A", "B", "X"] and out["viewedOnServer"] == ["X", "B", "A"]
    assert out["removedAtOnce"] == ["A", "X"] and out["removedOnServer"] == ["X", "A"]
    assert out["clearedAtOnce"] == []


def test_a_history_change_the_server_refused_is_taken_back(out):
    assert out["failedRemoveAtOnce"] == ["A"]
    assert out["failedRemoveAfterReload"] == ["A", "X"]


def test_undo_sends_the_entries_oldest_first(out):
    assert out["restoredAtOnce"] == ["A", "X"]
    # sent oldest first. The real database keeps whole seconds, so entries sent in the same second can swap places there
    assert out["restoredOnServer"] == ["X", "A"]


def test_one_restored_entry_comes_back_as_the_newest_on_the_page_and_on_the_server(out):
    assert out["restoredOneAfter"] == {"list": ["X", "A"], "server": ["A", "X"]}
    assert out["restoredOneReload"] == ["X", "A"]              # reading the server again gives the same order as the page showed


def test_the_login_merge_skips_a_product_that_is_gone_and_keeps_the_list_when_it_fails(out):
    assert out["mergeSkipsGone"] == {"server": ["X", "A"], "local": 0}
    for status, result in zip((500, 401, 0), out["mergeFailures"]):
        # the error comes out, this browser keeps its list for the next login, and the page shows the account's own list
        assert result == {"status": status, "rejected": True, "local": 1, "list": ["A", "X"]}, result


def test_a_removal_and_its_undo_reach_the_server_in_that_order(out):
    assert out["removeThenUndo"] == {"list": ["A"], "server": ["A"]}


def test_a_review_is_sent_as_the_api_wants_it_and_comes_back_in_the_page_shape(out):
    assert out["review"]["sent"] == {"rating": 4, "text": "Đẹp", "topics": ["Đúng size"]}      # a customer sends no phone
    assert out["review"]["result"] == {"ma": 7, "donHang": "VN123", "soSao": 4, "noiDung": "Đẹp",
                                       "luc": "2030-01-01T09:00:00", "chuDe": ["Đúng size"]}


def test_an_unticked_cart_line_stays_unticked_after_undo_and_after_changing_its_choices(out):
    # removing and restoring: each line keeps the tick it had, although the cart page forgot the ticks of removed lines
    assert out["undoKeepsTicks"] == {"plainTicked": False, "abTicked": True, "stored": 2}
    assert out["changedKeepsUntick"] == {"newKey": True, "xyTicked": False, "plainTicked": True}


def test_a_line_merged_into_another_keeps_the_tick_of_that_other_line(out):
    assert out["mergedKeepsTargetTick"] == {"abTicked": True, "lines": 1, "quantity": 2}
