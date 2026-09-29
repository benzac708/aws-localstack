"""Unit tests for the processor, run with moto (no LocalStack needed).

The handler touches only S3 and DynamoDB, both emulated by moto; the SQS
envelope is constructed directly, so the tests are fast and deterministic.
"""

import json
import os

import boto3
from moto import mock_aws

os.environ.setdefault("OUTPUT_BUCKET", "pipeline-output")
os.environ.setdefault("RECORDS_TABLE", "pipeline-records")
os.environ.pop("LOCALSTACK_HOSTNAME", None)  # force boto3 defaults -> moto

import main  # noqa: E402


def _s3_event(bucket, key):
    return {
        "Records": [
            {
                "body": json.dumps(
                    {
                        "Records": [
                            {
                                "s3": {
                                    "bucket": {"name": bucket},
                                    "object": {"key": key},
                                }
                            }
                        ]
                    }
                ),
                "receiptHandle": "test-handle",
            }
        ]
    }


@mock_aws
def test_handler_writes_digest_and_record():
    s3 = boto3.client("s3", region_name="us-east-1")
    s3.create_bucket(Bucket="pipeline-input")
    s3.create_bucket(Bucket="pipeline-output")
    s3.put_object(Bucket="pipeline-input", Key="readme.txt", Body="one\ntwo two\n")

    ddb = boto3.resource("dynamodb", region_name="us-east-1")
    ddb.create_table(
        TableName="pipeline-records",
        KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
        AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "S"}],
        BillingMode="PAY_PER_REQUEST",
    )

    result = main.handler(_s3_event("pipeline-input", "readme.txt"), None)

    assert result["processed"] == ["readme.txt"]

    digest = json.loads(
        s3.get_object(Bucket="pipeline-output", Key="readme.txt.json")["Body"].read()
    )
    assert digest["lines"] == 2
    assert digest["words"] == 3
    assert digest["chars"] == 12

    item = ddb.Table("pipeline-records").get_item(Key={"id": "readme.txt"})["Item"]
    assert item["words"] == 3
    assert "processed_at" in item


@mock_aws
def test_handler_handles_multiple_messages_in_one_invocation():
    s3 = boto3.client("s3", region_name="us-east-1")
    s3.create_bucket(Bucket="pipeline-input")
    s3.create_bucket(Bucket="pipeline-output")
    s3.put_object(Bucket="pipeline-input", Key="a.txt", Body="a")
    s3.put_object(Bucket="pipeline-input", Key="b.txt", Body="b b")

    ddb = boto3.resource("dynamodb", region_name="us-east-1")
    ddb.create_table(
        TableName="pipeline-records",
        KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
        AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "S"}],
        BillingMode="PAY_PER_REQUEST",
    )

    event = {
        "Records": [
            _s3_event("pipeline-input", "a.txt")["Records"][0],
            _s3_event("pipeline-input", "b.txt")["Records"][0],
        ]
    }
    result = main.handler(event, None)

    assert sorted(result["processed"]) == ["a.txt", "b.txt"]
    assert (
        ddb.Table("pipeline-records").get_item(Key={"id": "a.txt"})["Item"]["chars"]
        == 1
    )
    assert (
        ddb.Table("pipeline-records").get_item(Key={"id": "b.txt"})["Item"]["chars"]
        == 3
    )
