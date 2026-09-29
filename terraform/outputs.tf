output "input_bucket" {
  description = "Drop documents here to trigger the pipeline."
  value       = aws_s3_bucket.input.id
}

output "output_bucket" {
  description = "Transformed documents land here as <key>.json."
  value       = aws_s3_bucket.output.id
}

output "records_table" {
  description = "DynamoDB table with one item per processed document."
  value       = aws_dynamodb_table.records.name
}

output "processing_queue" {
  description = "Queue between S3 events and Lambda."
  value       = aws_sqs_queue.processing.name
}

output "dlq" {
  description = "Dead-letter queue (max 3 receive attempts)."
  value       = aws_sqs_queue.dlq.name
}

output "endpoint" {
  description = "LocalStack endpoint the AWS client must use."
  value       = var.aws_endpoint
}