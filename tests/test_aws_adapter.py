from botocore.exceptions import ClientError
from app.adapters import DynamoRepository, SQSQueue

class FakeDynamo:
    def __init__(self): self.writes=[]
    def put_item(self, **kw): self.writes.append(kw)

class DuplicateDynamo:
    def put_item(self, **kw):
        raise ClientError({"Error":{"Code":"ConditionalCheckFailedException","Message":"duplicate"}}, "PutItem")

class FakeSQS:
    def __init__(self): self.calls=[]
    def send_message(self,**kw): self.calls.append(kw)

def test_dynamo_conditional_write():
    client=FakeDynamo()
    repo=DynamoRepository(table="sample",client=client)
    assert repo.save_processed_once({"order_id":"abc","payload_hash":"def","sku":"ABC","quantity":2})
    assert client.writes[0]["ConditionExpression"]=="attribute_not_exists(order_id)"

def test_dynamo_duplicate_is_safe():
    repo=DynamoRepository(table="sample",client=DuplicateDynamo())
    assert repo.save_processed_once({"order_id":"abc"}) is False

def test_sqs_publish():
    sqs=FakeSQS()
    SQSQueue(queue_url="https://example.invalid/queue",client=sqs).publish({"sku":"ABC"})
    assert '"sku": "ABC"' in sqs.calls[0]["MessageBody"]
