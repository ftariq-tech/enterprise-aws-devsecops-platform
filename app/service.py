"""Transport-agnostic order acceptance and processing logic."""
import hashlib
import json
from typing import Protocol
from app.models import OrderRequest, OrderMessage

class Queue(Protocol):
    def publish(self, payload: dict) -> None: ...

class Repository(Protocol):
    def get(self, order_id: str) -> dict | None: ...
    def save_processed_once(self, payload: dict) -> bool: ...

def create_order(order: OrderRequest, idempotency_key: str, queue: Queue) -> str:
    """Same key -> same ID. SQS may still contain duplicates; worker handles those."""
    key = idempotency_key.strip()
    if not (8 <= len(key) <= 128) or any(ord(c) < 33 or ord(c) > 126 for c in key):
        raise ValueError("Idempotency-Key must contain 8–128 visible ASCII characters")
    order_id = hashlib.sha256(key.encode("ascii")).hexdigest()
    canonical = json.dumps(order.model_dump(), sort_keys=True, separators=(",", ":"))
    payload_hash = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    queue.publish(OrderMessage(order_id=order_id, payload_hash=payload_hash, **order.model_dump()).model_dump())
    return order_id

def process_message(raw: str, repo: Repository) -> str:
    """Acknowledge only after durable DB write (or proven duplicate)."""
    payload = OrderMessage.model_validate_json(raw)
    data = payload.model_dump()
    created = repo.save_processed_once(data)
    if created:
        return "processed"
    existing = repo.get(payload.order_id)
    if not existing or existing.get("payload_hash") != payload.payload_hash:
        # A reused idempotency key with a different request is poisonous.
        # Retrying leads to DLQ for investigation, rather than overwriting data.
        raise ValueError("Idempotency key reused with different order payload")
    return "duplicate"
