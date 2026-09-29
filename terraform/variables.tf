variable "aws_region" {
  description = "Region emulated by LocalStack."
  type        = string
  default     = "us-east-1"
}

variable "aws_endpoint" {
  description = "LocalStack single API endpoint."
  type        = string
  default     = "http://localhost:4566"
}

variable "input_bucket" {
  description = "Versioned source bucket the pipeline watches."
  type        = string
  default     = "pipeline-input"
}

variable "output_bucket" {
  description = "Bucket where transformed documents land."
  type        = string
  default     = "pipeline-output"
}

variable "records_table" {
  description = "DynamoDB table recording every processed document."
  type        = string
  default     = "pipeline-records"
}

variable "processing_queue" {
  description = "Queue that decouples S3 events from Lambda."
  type        = string
  default     = "pipeline-processing"
}

variable "dlq_name" {
  description = "Dead-letter queue for failed processing attempts."
  type        = string
  default     = "pipeline-dlq"
}

variable "lambda_name" {
  description = "Processor function name."
  type        = string
  default     = "pipeline-processor"
}

variable "lambda_runtime" {
  description = "Lambda runtime. boto3 ships with all supported runtime images, so the processor is dependency-free."
  type        = string
  default     = "python3.12"
}

variable "lambda_architecture" {
  description = "CPU architecture for the processor function."
  type        = string
  default     = "arm64"
}