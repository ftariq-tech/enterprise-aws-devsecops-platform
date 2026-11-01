"""FastAPI order submission service (asynchronous processing via SQS)."""
import hmac
import os
from fastapi import FastAPI, Header, HTTPException, status
from fastapi.responses import JSONResponse
from app.models import OrderRequest
from app.service import create_order
from app.adapters import MemoryQueue, MemoryRepository, SQSQueue, DynamoRepository

def create_app(queue=None, repo=None, token=None) -> FastAPI:
    mode = os.getenv("BACKEND", "memory")
    if mode == "aws" and not (token or os.getenv("ORDERS_API_TOKEN")):
        raise RuntimeError("ORDERS_API_TOKEN must be configured for AWS deployment")
    queue = queue if queue is not None else (SQSQueue() if mode == "aws" else MemoryQueue())
    repo = repo if repo is not None else (DynamoRepository() if mode == "aws" else MemoryRepository())
    expected_token = token if token is not None else os.getenv("ORDERS_API_TOKEN", "")
    api = FastAPI(title="Event-Driven Orders Demo", version="1.0.0", docs_url=None, redoc_url=None)

    def authorize(candidate: str | None):
        if expected_token and (not candidate or not hmac.compare_digest(candidate, expected_token)):
            raise HTTPException(status_code=401, detail="Unauthorized")

    @api.get("/health/live")
    def live(): return {"status": "alive"}

    @api.get("/health/ready")
    def ready(): return {"status": "ready"}  # Process readiness, not an AWS connectivity probe.

    @api.post("/v1/orders", status_code=status.HTTP_202_ACCEPTED)
    def submit(
        order: OrderRequest,
        idempotency_key: str = Header(..., alias="Idempotency-Key"),
        x_api_key: str | None = Header(None, alias="X-API-Key"),
    ):
        authorize(x_api_key)
        try:
            order_id = create_order(order, idempotency_key, queue)
        except ValueError as exc:
            raise HTTPException(status_code=422, detail=str(exc)) from exc
        return {"order_id": order_id, "status": "QUEUED"}

    @api.get("/v1/orders/{order_id}")
    def check_order(order_id: str, x_api_key: str | None = Header(None, alias="X-API-Key")):
        authorize(x_api_key)
        if len(order_id) != 64 or any(c not in "0123456789abcdef" for c in order_id):
            raise HTTPException(status_code=422, detail="Invalid order ID")
        record = repo.get(order_id)
        if record: return {"order_id": order_id, "status": record["status"]}
        return JSONResponse(status_code=202, content={"order_id": order_id, "status": "PENDING_OR_UNKNOWN"})

    return api

app = create_app()
