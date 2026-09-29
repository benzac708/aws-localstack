# ── Storage ───────────────────────────────────────────────────────────────────
# Versioned input bucket: the property that makes the pipeline safe is that a
# bad transformation never destroys the original, so the source is versioned by
# design and the transformation is written to a SEPARATE bucket, never in
# place. Both choices are intentional; either one alone is the classic accident.

resource "aws_s3_bucket" "input" {
  bucket        = var.input_bucket
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "input" {
  bucket = aws_s3_bucket.input.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket" "output" {
  bucket        = var.output_bucket
  force_destroy = true
}

# ── Queueing ──────────────────────────────────────────────────────────────────
# S3 events go to the queue, not to Lambda directly. The queue is what gives
# the pipeline its properties: a Lambda cold start or crash does not lose the
# event (SQS retains it), and a poison message does not wedge the pipeline
# (the DLQ redrive policy evicts it after three attempts).

resource "aws_sqs_queue" "processing" {
  name                       = var.processing_queue
  visibility_timeout_seconds = 30
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue" "dlq" {
  name = var.dlq_name
}

# The S3→SQS notification. The policy below is the least-privilege version of
# "this bucket may message this queue": the allow is scoped by aws:SourceArn,
# the condition real AWS enforces (and LocalStack does not -- noted in README).
resource "aws_s3_bucket_notification" "input" {
  bucket = aws_s3_bucket.input.id
  queue {
    queue_arn = aws_sqs_queue.processing.arn
    events    = ["s3:ObjectCreated:*"]
  }
}

data "aws_iam_policy_document" "s3_to_sqs" {
  statement {
    sid       = "AllowS3ToMessageQueue"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.processing.arn]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.input.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "processing" {
  queue_url = aws_sqs_queue.processing.id
  policy    = data.aws_iam_policy_document.s3_to_sqs.json
}

# ── Records ───────────────────────────────────────────────────────────────────
# One item per processed document: id (the S3 key), timestamp, and the
# metrics the processor extracted. PAY_PER_REQUEST keeps emulation honest with
# a real deployment (LocalStack ignores capacity either way).

resource "aws_dynamodb_table" "records" {
  name         = var.records_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}