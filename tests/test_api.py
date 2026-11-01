from fastapi.testclient import TestClient
from app.api import create_app
from app.adapters import MemoryQueue, MemoryRepository

def client(token=""):
    q, r = MemoryQueue(), MemoryRepository()
    return TestClient(create_app(queue=q, repo=r, token=token)), q, r

def test_accept_and_deterministic_id():
    c, q, _ = client()
    headers={"Idempotency-Key": "order-demo-001"}
    a = c.post("/v1/orders", json={"sku": "ABC-7", "quantity": 2}, headers=headers)
    b = c.post("/v1/orders", json={"sku": "ABC-7", "quantity": 2}, headers=headers)
    assert a.status_code == b.status_code == 202
    assert a.json()["order_id"] == b.json()["order_id"]
    assert len(q.messages) == 2  # SQS can duplicate; consumer is idempotent.

def test_reject_malformed_payload():
    c, q, _ = client()
    r=c.post("/v1/orders", json={"sku": "ABC", "quantity": -1},headers={"Idempotency-Key":"order-demo-002"})
    assert r.status_code == 422 and not q.messages

def test_invalid_key():
    c,_,_=client()
    r=c.post("/v1/orders",json={"sku":"ABC","quantity":1},headers={"Idempotency-Key":"bad"})
    assert r.status_code == 422

def test_api_token_enforced():
    c, _, _ = client(token="test-only-long-secret")
    p={"sku":"ABC","quantity":2}
    assert c.post("/v1/orders",json=p,headers={"Idempotency-Key":"order-demo-003"}).status_code == 401
    h={"Idempotency-Key":"order-demo-003","X-API-Key":"test-only-long-secret"}
    assert c.post("/v1/orders",json=p,headers=h).status_code == 202

def test_status_initially_pending():
    c,_,_=client()
    resp=c.post("/v1/orders",json={"sku":"ABC","quantity":2},headers={"Idempotency-Key":"order-demo-004"})
    got=c.get("/v1/orders/"+resp.json()["order_id"])
    assert got.status_code == 202 and got.json()["status"] == "PENDING_OR_UNKNOWN"
