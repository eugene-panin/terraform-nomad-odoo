.PHONY: help fmt lint module-tests

help:
	@echo "make fmt           tofu fmt, recursively"
	@echo "make lint          fmt check and tflint"
	@echo "make module-tests  tofu test of the module (TF_BINARY=terraform for terraform)"

fmt:
	tofu fmt -recursive

lint:
	tofu fmt -check -recursive
	tflint --init && tflint --recursive --config "$(CURDIR)/.tflint.hcl"

TF_BINARY ?= tofu

module-tests:
	$(TF_BINARY) init -backend=false -input=false >/dev/null && $(TF_BINARY) test
