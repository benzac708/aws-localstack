# The processor source is a directory; the archive provider zips it into a
# lambda deploy artifact. The code is the artifact source of truth -- no
# hand-made zip that can drift from the tree.

data "archive_file" "processor" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/processor"
  output_path = "${path.module}/.cache/processor.zip"
  excludes    = ["__pycache__", "tests"]
}

# ── IAM ───────────────────────────────────────────────────────────────────────
# The role is least-privilege by construction: three statements covering
# exactly the surface the handler touches (queue in, s3 in/out, table record,
# logs). LocalStack does not enforce IAM, which is the first thing the README
# says -- but the policies are still written as if they will be enforced,
# because the point of the project is the policies.

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "processor_permissions" {
  statement {
    sid       = "PollQueue"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.processing.arn]
  }
  statement {
    sid       = "ReadInput"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.input.arn}/*"]
  }
  statement {
    sid       = "WriteOutput"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.output.arn}/*"]
  }
  statement {
    sid       = "RecordResult"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.records.arn]
  }
  statement {
    sid       = "ShipLogs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.lambda_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "processor" {
  name   = "processor-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.processor_permissions.json
}

# ── Function + wiring ─────────────────────────────────────────────────────────
# The SQS event source mapping is the decoupling point in the other direction:
# Lambda polls the queue instead of S3 invoking Lambda directly, so the
# processor owns its timing and failures do not bubble back into storage.

resource "aws_lambda_function" "processor" {
  filename         = data.archive_file.processor.output_path
  source_code_hash = data.archive_file.processor.output_base64sha256
  function_name    = var.lambda_name
  role             = aws_iam_role.lambda.arn
  runtime          = var.lambda_runtime
  handler          = "main.handler"
  timeout          = 30
  memory_size      = 128
  # The processor runs natively on the host's architecture. The AWS provider
  # defaults to x86_64, which on this ARM box makes LocalStack launch an
  # amd64 runtime against an arm64-only image -- exec format error. The
  # variable keeps the config honest for both host types.
  architectures = [var.lambda_architecture]

  environment {
    variables = {
      OUTPUT_BUCKET = aws_s3_bucket.output.id
      RECORDS_TABLE = aws_dynamodb_table.records.id
    }
  }
}

resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn = aws_sqs_queue.processing.arn
  function_name    = aws_lambda_function.processor.arn
  batch_size       = 1
  enabled          = true
}