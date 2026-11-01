"""Long-polling SQS worker; leave failed messages for SQS redrive to DLQ."""
import json
import logging
import os
import signal
from app.adapters import DynamoRepository
from app.service import process_message
import boto3

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"), format="%(message)s")
logger = logging.getLogger("orders.worker")
STOP = False

def stop(*_):
    global STOP
    STOP = True

def run(queue_url=None, sqs=None, repo=None):
    queue_url = queue_url or os.environ["QUEUE_URL"]
    sqs = sqs or boto3.client("sqs")
    repo = repo or DynamoRepository()
    logger.info(json.dumps({"event": "worker_started"}))
    while not STOP:
        result = sqs.receive_message(
            QueueUrl=queue_url, MaxNumberOfMessages=5,
            WaitTimeSeconds=15, VisibilityTimeout=60,
        )
        for msg in result.get("Messages", []):
            try:
                outcome = process_message(msg["Body"], repo)
                sqs.delete_message(QueueUrl=queue_url, ReceiptHandle=msg["ReceiptHandle"])
                logger.info(json.dumps({"event": "message_acked", "result": outcome}))
            except Exception:
                # Do not delete: poison messages reach the dead-letter queue.
                logger.exception(json.dumps({"event": "message_failed"}))

if __name__ == "__main__":
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    run()
