provider "aws" {
  region = var.aws_region

  # LocalStack accepts any credential pair; these are the conventional ones.
  # Nothing here ever touches a real account: the endpoint list below is the
  # entire difference between this and a production provider block.
  access_key = "test"
  secret_key = "test"

  # The emulated STS GetCallerIdentity returns the LocalStack test account
  # (000000000000), which is what gives resources their "real" ARNs.
  #
  # AWS validation/checks are skipped because they round-trip to a real
  # metadata service or live region that does not exist here.
  skip_credentials_validation = true
  skip_metadata_api_check     = true

  # LocalStack serves S3 via path-style addressing. Real S3 uses virtual-host;
  # the flag is harmless on AWS and required here.
  s3_use_path_style = true

  # One endpoint for every service: this is LocalStack's single-Port contract.
  # Each service entry is explicit so a reviewer can see the full blast radius
  # of what the emulation covers, rather than a magic "localstack" shorthand.
  endpoints {
    s3         = var.aws_endpoint
    sqs        = var.aws_endpoint
    lambda     = var.aws_endpoint
    dynamodb   = var.aws_endpoint
    iam        = var.aws_endpoint
    sts        = var.aws_endpoint
    cloudwatch = var.aws_endpoint
    logs       = var.aws_endpoint
  }
}