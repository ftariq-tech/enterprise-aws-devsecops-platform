import json
import pytest
from app.adapters import MemoryQueue, MemoryRepository
from app.models import OrderRequest
from app.service import create_order, process_message

def message(key="an-order-key-1", sku="SKU_1"):
    q=MemoryQueue()
    create_order(OrderRequest(sku=sku,quantity=3), key, q)
    return q.messages[0]

def test_worker_idempotency():
    repo=MemoryRepository()
    raw=message()
    assert process_message(raw,repo)=="processed"
    assert process_message(raw,repo)=="duplicate"
    assert len(repo.items)==1

def test_same_key_different_payload_rejected():
    repo=MemoryRepository()
    process_message(message(sku="AAA"),repo)
    with pytest.raises(ValueError, match="reused"):
        process_message(message(sku="BBB"),repo)

def test_poison_message_rejected():
    with pytest.raises(Exception):
        process_message('{"bad": "message"}',MemoryRepository())

def test_saved_status():
    repo=MemoryRepository()
    payload=json.loads(message())
    process_message(json.dumps(payload),repo)
    assert repo.get(payload["order_id"])["status"]=="COMPLETED"
