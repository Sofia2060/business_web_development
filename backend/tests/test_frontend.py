"""Tests that Flask serves the web pages and their files at the same address as the API."""
import posixpath
import re
from urllib.parse import urlsplit

import pytest

from app.config import FRONTEND_DIR

PAGES = sorted(p.relative_to(FRONTEND_DIR).as_posix() for p in (FRONTEND_DIR / "src" / "pages").glob("*/*.html"))
LOCAL_REF = re.compile(r'(?:href|src)="([^"]+)"|"[A-Za-z]+": "([^"]+\.[a-z]{2,5}[^"]*|[^"]*/)"')


@pytest.fixture
def client(db_ready):
    from app import create_app
    return create_app().test_client()


def test_root_leads_to_the_client_home_page(client):
    res = client.get("/")
    assert res.status_code == 200 and "src/pages/client/index.html" in res.get_data(as_text=True)


def test_there_are_pages_to_test():
    assert len(PAGES) >= 25     # 18 client pages and 7 admin pages


def test_html_is_served_as_utf8_so_vietnamese_text_is_not_garbled(client):
    # The pages do not declare a charset themselves, so the server header must.
    res = client.get("/src/pages/client/index.html")
    assert "text/html" in res.content_type and "charset=utf-8" in res.content_type.lower()
    assert "Trang sức cao cấp" in res.get_data(as_text=True)


@pytest.mark.parametrize("path,kind", [
    ("/src/css/base/variables.css", "text/css"),
    ("/src/js/core/common.js", "javascript"),
    ("/mock-data/products.json", "application/json"),
    ("/public/fonts/fonts.css", "text/css"),
    ("/public/images/logo/favicon.svg", "image/svg+xml"),
])
def test_files_have_the_right_type(client, path, kind):
    res = client.get(path)
    assert res.status_code == 200 and kind in res.content_type


def test_every_page_loads_and_every_file_it_uses_exists(client):
    """Open all pages and fetch every stylesheet, script, image, font, data file and page link they mention."""
    checked, missing = set(), []
    for page in PAGES:
        url = "/" + page
        assert client.get(url).status_code == 200, url
        html = (FRONTEND_DIR / page).read_text(encoding="utf-8")
        for match in LOCAL_REF.finditer(html):
            ref = match.group(1) or match.group(2)
            if re.match(r"(https?:|mailto:|tel:|data:|javascript:|#)", ref) or "__" in ref or ref.endswith("/"):
                continue          # skip external links, placeholders and folder paths such as "../../../mock-data/"
            target = posixpath.normpath(posixpath.join(posixpath.dirname(url), urlsplit(ref).path))
            if target in checked or not urlsplit(ref).path:
                continue
            checked.add(target)
            if client.get(target).status_code != 200:
                missing.append(f"{url} -> {target}")
    assert not missing, missing[:10]
    assert len(checked) > 60     # sanity check that the crawl really found files


@pytest.mark.parametrize("path", ["/README.md", "/src/../README.md", "/%2e%2e/backend/app/config.py",
                                  "/src/%2e%2e/%2e%2e/backend/app/config.py", "/..%2f..%2f.env", "/.env", "/backend/app/config.py"])
def test_files_outside_the_web_folders_are_not_served(client, path):
    res = client.get(path)
    assert res.status_code == 404
    body = res.get_data(as_text=True)
    assert "db_connection_string" not in body and "SECRET_KEY" not in body and "Vinora@2026" not in body


def test_api_still_works_next_to_the_files(client):
    res = client.get("/api/products?limit=1")
    assert res.status_code == 200 and res.is_json and res.get_json()["total"] == 443
    assert client.get("/api/products/NDINO131LDIA").get_json()["SKU"] == "NDINO131LDIA"


def test_unknown_api_paths_and_wrong_methods_answer_in_json(client):
    for res in (client.get("/api/nothing-here"), client.post("/api/products"), client.delete("/api/auth/me")):
        assert res.is_json and "error" in res.get_json()
    assert client.get("/api/nothing-here").status_code == 404
    assert client.post("/api/products").status_code == 405
    big = client.post("/api/auth/login", json={"email": "x" * 20000})
    assert big.status_code == 413 and big.is_json


def test_missing_page_keeps_the_normal_error_page(client):
    res = client.get("/src/pages/client/not-a-page.html")
    assert res.status_code == 404 and not res.is_json
