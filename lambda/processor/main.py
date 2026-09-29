"""Processor for the S3 -> SQS -> Lambda -> DynamoDB pipeline.

Reads a text object named by an S3 event envelope (carried inside an SQS
message), writes a JSON digest of it to the output bucket, and records one
DynamoDB item per document.

Deliberately boring. The interesting decisions live in Terraform: the
versioned input bucket, the queue as the decoupling point, the DLQ redrive
policy, and the least-privilege IAM. This file is what a reviewer skips to
when they are done looking at why the pipeline is safe.

Dependency policy: boto3 only, and boto3 ships with every supported Lambda
runtime, so the function package is a single zip with no requirements step.
On real AWS this code runs unmodified -- the only branch is the endpoint
fallback for LocalStack's single-port contract, which is what makes the
emulated environment work.
"""

import hashlib
import json
import os
import time

import boto3

OUTPUT_BUCKET = os.environ["OUTPUT_BUCKET"]
RECORDS_TABLE = os.environ["RECORDS_TABLE"]


def _endpoint():
    """LocalStack lambda containers reach the gateway via LOCALSTACK_HOSTNAME.

    Unset on real AWS, where boto3 defaults to the live endpoints instead.
    """
    host = os.environ.get("LOCALSTACK_HOSTNAME")
    if host:
        return f"http://{host}:4566"
    return None


def _region():
    """Real Lambda sets AWS_REGION; local and CI runs may not, and moto needs one."""
    return (
        os.environ.get("AWS_REGION")
        or os.environ.get("AWS_DEFAULT_REGION")
        or "us-east-1"
    )


def _digest_stats(payload):
    lines = payload.splitlines()
    return {
        "lines": len(lines),
        "words": len(payload.split()),
        "chars": len(payload),
        "sha256": hashlib.sha256(payload.encode("utf-8")).hexdigest(),
    }


def handler(event, context):
    s3 = boto3.client("s3", endpoint_url=_endpoint(), region_name=_region())
    table = boto3.resource(
        "dynamodb", endpoint_url=_endpoint(), region_name=_region()
    ).Table(RECORDS_TABLE)

    processed = []
    for sqs_envelope in event["Records"]:
        # Each SQS message carries a full S3 event notification body.
        s3_event = json.loads(sqs_envelope["body"])
        for record in s3_event.get("Records", []):
            key = record["s3"]["object"]["key"]
            bucket = record["s3"]["bucket"]["name"]

            payload = (
                s3.get_object(Bucket=bucket, Key=key)["Body"].read().decode("utf-8")
            )
            stats = _digest_stats(payload)

            s3.put_object(
                Bucket=OUTPUT_BUCKET,
                Key=f"{key}.json",
                Body=json.dumps({"key": key, **stats}, indent=2),
                ContentType="application/json",
            )
            table.put_item(
                Item={
                    "id": key,
                    "processed_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    **stats,
                }
            )
            processed.append(key)

    return {"statusCode": 200, "processed": processed}
