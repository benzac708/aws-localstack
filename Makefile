# Local development loop for the aws-localstack pipeline.
# CI runs the same steps; see .github/workflows/ci.yml for the canonical gate.

TF          := terraform
VENV        := .venv
PY          := $(VENV)/bin/python
TF_DIR      := terraform

# Lambda runs natively on the host architecture (see terraform/lambda.tf).
# The AWS provider defaults to x86_64, which breaks LocalStack on ARM hosts;
# the matrix goes the other way on amd64 machines, where arm64 is the break.
export TF_VAR_lambda_architecture := $(shell uname -m | sed 's/aarch64/arm64/')

.PHONY: up down plan apply destroy verify test fmt tf-validate lint clean

up:
	docker compose up -d localstack
	docker compose run --rm localstack /bin/sh -c 'until curl -sf http://localhost:4566/_localstack/health >/dev/null; do sleep 1; done' 2>/dev/null || true

down:
	docker compose down

$(VENV)/bin/python:
	python3 -m venv $(VENV)
	$(PY) -m pip install --quiet --upgrade pip

$(VENV)/lib/python3*/site-packages/boto3: $(VENV)/bin/python lambda/tests/requirements.txt
	$(PY) -m pip install --quiet -r lambda/tests/requirements.txt && touch $@

plan: up
	cd $(TF_DIR) && $(TF) init -backend=false -reconfigure && $(TF) plan

apply: up
	cd $(TF_DIR) && $(TF) init -backend=false -reconfigure && $(TF) apply -auto-approve

destroy:
	cd $(TF_DIR) && $(TF) destroy -auto-approve
	docker compose down

verify: up $(VENV)/lib/python3*/site-packages/boto3
	$(PY) scripts/smoke.py

test: $(VENV)/lib/python3*/site-packages/boto3
	$(PY) -m pytest lambda/processor/tests -q
	cd $(TF_DIR) && $(TF) fmt -check && $(TF) validate

fmt:
	cd $(TF_DIR) && $(TF) fmt -recursive

tf-validate:
	cd $(TF_DIR) && $(TF) init -backend=false -reconfigure && $(TF) validate

lint: $(VENV)/lib/python3*/site-packages/boto3
	$(VENV)/bin/ruff check lambda/processor
	$(VENV)/bin/ruff format --check lambda/processor

clean:
	rm -rf $(VENV) terraform/.terraform terraform/.cache terraform/.terraform.lock.hcl
