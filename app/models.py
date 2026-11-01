"""Shared, strict data contract for API and queue messages."""
from pydantic import BaseModel, Field, ConfigDict

class OrderRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    sku: str = Field(min_length=1, max_length=40, pattern=r"^[A-Za-z0-9_-]+$")
    quantity: int = Field(ge=1, le=100, strict=True)

class OrderMessage(OrderRequest):
    order_id: str = Field(pattern=r"^[0-9a-f]{64}$")
    payload_hash: str = Field(pattern=r"^[0-9a-f]{64}$")
