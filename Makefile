SHELL := /bin/bash
.PHONY: help build extract verify clean

IMAGE_NAME ?= lambda-layer-builder
OUTPUT_ZIP ?= layer.zip

help:
	@echo "AWS Lambda Layer Squeeze Toolchain"
	@echo "Commands:"
	@echo "  make build         Build Docker image with BuildKit and run dependency surgery"
	@echo "  make extract       Export the pruned layer into layer.zip"
	@echo "  make verify        Run verification and smoke tests in Lambda runtime container"
	@echo "  make clean         Remove local build artifacts and output archives"

build:
	DOCKER_BUILDKIT=1 docker build \
		--ssh default \
		--target runtime-verifier \
		-t $(IMAGE_NAME) .

extract: build
	@echo "Extracting layer artifacts to $(OUTPUT_ZIP)..."
	@mkdir -p dist/python
	@container_id=$$(docker create $(IMAGE_NAME)); \
		docker cp $$container_id:/opt/python dist/; \
		docker rm $$container_id
	@cd dist && zip -r9 ../$(OUTPUT_ZIP) python
	@rm -rf dist
	@echo "Created $(OUTPUT_ZIP) successfully!"
	@ls -lh $(OUTPUT_ZIP)

verify: build
	docker run --rm --entrypoint python3 $(IMAGE_NAME) /verify_layer.py /opt/python
	docker run --rm --entrypoint python3 $(IMAGE_NAME) /test_smoke.py

clean:
	rm -rf dist $(OUTPUT_ZIP)
