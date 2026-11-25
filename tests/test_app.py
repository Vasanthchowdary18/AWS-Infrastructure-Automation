import pytest

from app.main import create_app


@pytest.fixture
def client():
    app = create_app()
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


def test_index(client):
    resp = client.get("/")
    assert resp.status_code == 200
    body = resp.get_json()
    assert "message" in body
    assert "version" in body


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ok"


def test_ready(client):
    resp = client.get("/ready")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ready"


def test_add_ok(client):
    resp = client.get("/api/add?a=2&b=3.5")
    assert resp.status_code == 200
    assert resp.get_json()["result"] == 5.5


def test_add_bad_input(client):
    resp = client.get("/api/add?a=x&b=1")
    assert resp.status_code == 400


def test_metrics(client):
    client.get("/health")
    resp = client.get("/metrics")
    assert resp.status_code == 200
    assert b"app_http_requests_total" in resp.data
