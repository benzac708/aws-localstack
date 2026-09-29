"""End-to-end smoke test for the local pipeline.

Requires: LocalStack up (docker compose up), Terraform applied (make apply).
Drops a document into the input bucket, then polls DynamoDB until the
processor has run (bounded), and asserts the transformed output exists.

Run with:  .venv/bin/python scripts/smoke.py   (or: make verify)
"""

import json
import os
import sys
import time

import boto3

ENDPOINT = os.environ.get("AWS_ENDPOINT_URL", "http://localhost:4566")
INPUT_BUCKET = os.environ.get("PIPELINE_INPUT_BUCKET", "pipeline-input")
OUTPUT_BUCKET = os.environ.get("PIPELINE_OUTPUT_BUCKET", "pipeline-output")
RECORDS_TABLE = os.environ.get("PIPELINE_RECORDS_TABLE", "pipeline-records")
KEY = "smoke.txt"
BODY = "line one\nline two\nline three\n"


def _s3():
    return boto3.client("s3", endpoint_url=ENDPOINT, region_name="us-east-1")


def _records_table():
    return boto3.resource(
        "dynamodb", endpoint_url=ENDPOINT, region_name="us-east-1"
    ).Table(RECORDS_TABLE)


def wait_for_processor(timeout=90):
    table = _records_table()
    deadline = time.time() + timeout
    while time.time() < deadline:
        got = table.get_item(Key={"id": KEY}).get("Item")
        if got:
            return got
        time.sleep(2)
    raise SystemExit(f"timeout: no DynamoDB record for '{KEY}' after {timeout}s")


def main():
    s3 = _s3()
    print(f"endpoint   : {ENDPOINT}")
    print(f"input  ->  : s3://{INPUT_BUCKET}/{KEY}")
    s3.put_object(Bucket=INPUT_BUCKET, Key=KEY, Body=BODY)

    record = wait_for_processor()
    print(f"record     : {json.dumps(record, indent=2, default=str)}")

    digest = json.loads(
        s3.get_object(Bucket=OUTPUT_BUCKET, Key=f"{KEY}.json")["Body"].read()
    )
    assert digest["words"] == 6, digest
    assert record["words"] == 6, record
    print(f"output ->  : s3://{OUTPUT_BUCKET}/{KEY}.json")
    print("SMOKE OK")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001 -- smoke script fails loudly
        print(f"SMOKE FAILED: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
