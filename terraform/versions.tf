terraform {
  # The only interface LocalStack guarantees is the AWS API; the Terraform
  # version is a floor, not a treadmill.
  required_version = "~> 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.6"
    }
  }

  # Local backend, deliberately. This emulates AWS on a local box: state is
  # throwaway and the config is the portable artifact. A real deployment would
  # point this at an S3 backend with DynamoDB locking -- the config does not
  # change for that, only this block does.
}