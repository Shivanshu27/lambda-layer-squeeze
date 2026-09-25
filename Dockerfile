# syntax=docker/dockerfile:1.4
# Stage 1: Build & Surgery Environment
ARG PYTHON_VERSION=3.11
FROM public.ecr.aws/sam/build-python${PYTHON_VERSION}:latest AS builder

WORKDIR /build

# Install required build tools & binary inspection utilities
RUN yum update -y && \
    yum install -y binutils file tar gzip git openssh-clients && \
    yum clean all && \
    rm -rf /var/cache/yum

# Target layer structure for AWS Lambda runtime
ENV LAYER_DIR=/opt/python
RUN mkdir -p ${LAYER_DIR}

COPY requirements.txt .
COPY scripts/prune_layer.sh /usr/local/bin/prune_layer.sh
RUN chmod +x /usr/local/bin/prune_layer.sh

# Mount SSH agent securely during pip install without baking private keys into layers
# Enforce pre-built binary wheels to eliminate accidental compilation from source
RUN --mount=type=ssh \
    pip install \
        --no-cache-dir \
        --target ${LAYER_DIR} \
        --only-binary=:all: \
        -r requirements.txt

# Run dependency surgery to strip debug symbols and trim leaked tooling
RUN /usr/local/bin/prune_layer.sh ${LAYER_DIR}

# Stage 2: Verification and Packaging
FROM public.ecr.aws/lambda/python:${PYTHON_VERSION} AS runtime-verifier

WORKDIR /var/task

ENV PYTHONPATH="/opt/python:${PYTHONPATH}"
ENTRYPOINT []

# Copy the pruned layer into the Lambda runtime search path
COPY --from=builder /opt/python /opt/python

COPY scripts/verify_layer.py /verify_layer.py
COPY scripts/test_smoke.py /test_smoke.py

# Verify layer size is <= 250MB and execute smoke tests in standard Lambda environment
RUN python3 /verify_layer.py /opt/python && \
    python3 /test_smoke.py

# Stage 3: Artifact Export
FROM scratch AS exporter
COPY --from=builder /opt/python /opt/python
