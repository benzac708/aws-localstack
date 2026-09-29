# aws-localstack

A serverless ingestion pipeline — **S3 → SQS → Lambda → DynamoDB** — provisioned
with Terraform and run end-to-end against [LocalStack](https://www.localstack.cloud/)
(the free AWS emulator), with a dead-letter queue on the processing path.

It is the AWS counterpart to the k8s estate: the same priorities — honest
trade-offs, least privilege, CI that actually executes the thing — applied to
the managed-services world.

**CI:** public repository, so GitHub Actions runs on free minutes (no billing
dependency): lint, unit tests (moto), Terraform `validate`, then a real
emulated cycle — LocalStack boot → `terraform apply` → smoke test → `terraform
destroy`. Every push proves the pipeline works, not just that it parses.

## What it does

```
 s3://pipeline-input (versioned)
        │  put object        ┌─────────────────────┐
        ▼                    │ pipeline-processor  │
   SQS ──────────────────────► lambda (python3.12) │
   (event notification,      │   reads the object,  │
    DLQ after 3 attempts)    │   digests it)        │
                             └──────────┬──────────┘
                              s3 put    │  ddb put
                              (digest)  ▼
                     s3://pipeline-output      DynamoDB: pipeline-records
                          <key>.json           one item per document
```

The design decisions live in
[`terraform/`](terraform/): the input bucket is **versioned** and transformations
write to a **separate** bucket (never in place); the **queue** — not a direct S3
→ Lambda invocation — is what makes events survive cold starts and crashes; the
**DLQ** (max 3 receive attempts) keeps a poison message from wedging the
pipeline; the Lambda **IAM role** is three statements covering exactly the
surface the handler touches.

## Why LocalStack

The alternative for this demo is nothing: you do not make a real AWS account
for every portfolio project. LocalStack emulates the AWS API on one port with
docker, so the workflow a real team runs — write HCL, apply, watch it work,
tear it down — is the same one here, minus the invoice. The limits are real
and are the first thing to read before trusting the demo:

- **IAM is permissive.** LocalStack creates roles and policies but does not
  enforce them. The policies in this repo are written as if they will be
  enforced — that is the point of having them — but emulation cannot prove it.
- **No quotas, no billing, no rate limits.** The provider's ceilings are the
  only control LocalStack exercises.
- **Tail latency is local.** Lambda execution happens in a docker container on
  your box; nothing here measures cloud latency.
- **Services are namespaced under one account** (`000000000000`) and one
  region (`us-east-1`). Multi-account/multi-region behaviour is not exercised.

This makes it a *pipeline demo*, not a *security audit* — and it says so rather
than pretending otherwise.

## Running it locally

```bash
# 0) one-time: a venv with the test/lint drivers
make .venv/bin/python
make test        # ruff + moto unit tests + terraform validate

# 1) boot the emulator
docker compose up -d localstack

# 2) provision the whole pipeline
make apply       # terraform init + apply against http://localhost:4566

# 3) prove it end-to-end
make verify      # put an object, wait for the record, assert the digest

# 4) tear down
make destroy
```

Or in one breath, since `apply` and `verify` depend on `up`:

```bash
make apply && make verify
```

## Structure

```
terraform/          provider block (endpoint pinning), resources, IAM, lambda
lambda/processor/   the one handler — boto3 only, zero dependencies
lambda/processor/tests/  moto-based unit tests (no emulator needed)
scripts/smoke.py    end-to-end probe: put → wait → assert
.github/workflows/ci.yml  the gate described above
```

## Configuration

The Terraform `aws` provider is pinned to the LocalStack endpoint in
[`terraform/providers.tf`](terraform/providers.tf) — the whole file exists to
make the single difference between "against LocalStack" and "against AWS"
legible. To point the same config at a real account: delete the `endpoints`
block and supply real credentials. Nothing else changes.

The Lambda function runs natively on the host architecture
(`TF_VAR_lambda_architecture`, see [`terraform/lambda.tf`](terraform/lambda.tf)).
The AWS provider defaults to `x86_64`, which on an ARM host makes LocalStack
launch an amd64 runtime against an arm64 image — `exec format error`. The
Makefile and CI pass the architecture of the machine they run on; you only
notice this variable if you read the logs, which is the point.

## A note on time

A cold LocalStack is not fast. Each service boots on first use, SQS create
operations carry a ~20-40s emulation lag, and the first Lambda invocation
spins up a runtime container. Expect `make apply` to take one to two minutes
and the first smoke run to add a few tens of seconds. The pipeline itself is
seconds once warm — the slowness is the emulator's, not the config's.

## Licence

MIT — see [LICENSE](LICENSE).