"""AWS adapters; local test doubles implement the same interface."""
import json
import os
import boto3
from botocore.exceptions import ClientError

class MemoryQueue:
    def __init__(self): self.messages = []
    def publish(self, payload: dict) -> None: self.messages.append(json.dumps(payload))

class MemoryRepository:
    def __init__(self): self.items = {}
    def get(self, order_id: str): return self.items.get(order_id)
    def save_processed_once(self, payload: dict) -> bool:
        if payload["order_id"] in self.items: return False
        self.items[payload["order_id"]] = {**payload, "status": "COMPLETED"}
        return True

class SQSQueue:
    def __init__(self, queue_url=None, client=None):
        self.queue_url = queue_url or os.environ["QUEUE_URL"]
        self.client = client or boto3.client("sqs")
    def publish(self, payload: dict) -> None:
        self.client.send_message(QueueUrl=self.queue_url, MessageBody=json.dumps(payload))

class DynamoRepository:
    def __init__(self, table=None, client=None):
        self.table = table or os.environ["ORDERS_TABLE"]
        self.client = client or boto3.client("dynamodb")
    def get(self, order_id: str):
        response = self.client.get_item(
            TableName=self.table,
            Key={"order_id": {"S": order_id}},
            ConsistentRead=True,
        )
        item = response.get("Item")
        if not item: return None
        return {k: v["S"] for k, v in item.items()}
    def save_processed_once(self, payload: dict) -> bool:
        item = {k: {"S": str(v)} for k, v in payload.items()}
        item["status"] = {"S": "COMPLETED"}
        try:
            self.client.put_item(
                TableName=self.table,
                Item=item,
                ConditionExpression="attribute_not_exists(order_id)",
            )
            return True
        except ClientError as exc:
            if exc.response.get("Error", {}).get("Code") == "ConditionalCheckFailedException":
                return False
            raise
