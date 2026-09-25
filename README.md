# AWS Lambda Layer Squeeze 🗜️

[![CI](https://github.com/Shivanshu27/lambda-layer-squeeze/actions/workflows/ci.yml/badge.svg)](https://github.com/Shivanshu27/lambda-layer-squeeze/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Python: 3.11](https://img.shields.io/badge/Python-3.11-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![AWS: Lambda](https://img.shields.io/badge/AWS-Lambda_Layer-FF9900?logo=awslambda&logoColor=white)](https://aws.amazon.com/lambda/)
[![Docker: BuildKit](https://img.shields.io/badge/Docker-BuildKit_SSH_Mount-2496ED?logo=docker&logoColor=white)](https://docs.docker.com/build/building/secrets/#ssh-mounts)

> Production-grade reference implementation for packaging computer vision (OpenCV Headless, Pillow, NumPy) and neural network inference engines (ONNX Runtime / TorchScript) under AWS Lambda's strict **250 MB uncompressed limit**, eliminating credential leakage via Docker BuildKit SSH mounts.

---

## 📌 The Problem: The 250 MB AWS Limit Wall

When packaging modern machine learning models and computer vision pipelines into serverless architectures:
1. **AWS Lambda Limit**: Lambda enforces a strict **250 MB uncompressed quota** across all attached layers and function code (and 50 MB zipped direct upload).
2. **Naive Bloat & Leaked Tooling**: Standard installations frequently pull in transitive documentation themes (`sphinx_rtd_theme`), test frameworks (`pytest`), duplicate SDKs (`boto3`/`botocore`, which are already provided natively by the Lambda execution environment), and unstripped C-extension debugging symbols, causing deployment failures:
   ```text
   ResourceConflictException: Unzipped size must be smaller than 262144000 bytes
   ```
3. **Training vs Inference Runtimes**: Standard PyTorch wheels on PyPI exceed 450 MB because they bundle the full training engine, autograd, Inductor, and compiler templates. Production serverless architectures export trained models to lightweight inference runtimes (such as ONNX Runtime or stripped TorchScript C++ binaries) to stay comfortably within serverless quotas.
4. **Private Repository Credential Leaks**: Installing internal packages often involves baking Git credentials, SSH private keys, or GitHub Personal Access Tokens into intermediate Docker image layers—a critical security liability.

---

## 🏗️ Architecture & Pipeline Overview

```text
+-----------------------------------------------------------------------------------------+
|                                BUILD & SURGERY PIPELINE                                 |
+-----------------------------------------------------------------------------------------+
|                                                                                         |
|  [Developer Workstation / CI]                                                           |
|       |                                                                                 |
|       | (ssh-agent socket mounted via Docker BuildKit)                                  |
|       v                                                                                 |
|  +-----------------------------------------------------------------------------------+  |
|  | Multi-Stage Dockerfile (Syntax: docker/dockerfile:1.4)                             |  |
|  |                                                                                   |  |
|  | 1. Secure Dependency Ingestion                                                    |  |
|  |    RUN --mount=type=ssh pip install --only-binary=:all: --target /opt/python ...  |  |
|  |    * No private SSH keys copied into layers                                       |  |
|  |    * Ephemeral socket communication                                               |  |
|  |    * Enforced binary wheels prevent silent, massive C-extension source builds     |  |
|  |                                                                                   |  |
|  | 2. Dependency Surgery (scripts/prune_layer.sh)                                    |  |
|  |    * Drops duplicate SDKs (boto3, botocore, s3transfer)                           |  |
|  |    * Removes leaked dev tooling (pytest, sphinx, pre-commit, babel)               |  |
|  |    * strip --strip-unneeded *.so (Removes ELF debugging symbols & notes)          |  |
|  |    * Prunes __pycache__, tests/, doc/, *.c, *.h, *.pxd, *.md                      |  |
|  |    * Cleans .dist-info/RECORD & unnecessary package metadata                      |  |
|  +-----------------------------------------------------------------------------------+  |
|       |                                                                                 |
|       v                                                                                 |
|  +-----------------------------------------------------------------------------------+  |
|  | Verification Stage (public.ecr.aws/lambda/python:3.11)                            |  |
|  |    * /verify_layer.py: Validates uncompressed size <= 250 MB                      |  |
|  |    * /test_smoke.py: Validates OpenCV image transforms & tensor inference math    |  |
|  +-----------------------------------------------------------------------------------+  |
|       |                                                                                 |
|       v                                                                                 |
|  [layer.zip: <250 MB uncompressed / <50 MB zipped deployment artifact]                  |
|                                                                                         |
+-----------------------------------------------------------------------------------------+
```

---

## 🔒 Security: Why BuildKit SSH Mounts?

Most naive CI configurations install private dependencies by passing GitHub tokens or SSH keys as build arguments:

```dockerfile
# ❌ ANTI-PATTERN: Security Risk
ARG GITHUB_TOKEN
RUN git clone https://${GITHUB_TOKEN}@github.com/org/private-repo.git
# Even if deleted in subsequent steps, GITHUB_TOKEN persists in image layer history!
```

This reference implementation uses BuildKit's secret/SSH forwarding:

```dockerfile
# ✅ PRODUCTION PATTERN: Zero Credential Persistence
# syntax=docker/dockerfile:1.4
RUN --mount=type=ssh pip install --only-binary=:all: -r requirements.txt
```

- Mounts the host's existing `ssh-agent` UNIX socket temporarily into the running container during the `RUN` step.
- Private keys never touch the container filesystem or metadata layer history.
- Works identically on local developer machines and CI runners (e.g. GitHub Actions).

---

## 🚀 Quickstart

### Prerequisites
- Docker Engine >= 20.10 with BuildKit enabled (`export DOCKER_BUILDKIT=1`).
- `make` and `zip`.
- An active SSH agent if installing private repositories (`eval $(ssh-agent); ssh-add ~/.ssh/id_ed25519`).

### 1. Build and Run Dependency Surgery
```bash
make build
```

### 2. Verify Size & Execution Smoke Tests
```bash
make verify
```

Sample output:
```text
Analyzing layer footprint at: /opt/python
------------------------------------------------------------
Package / Item                      | Size           
------------------------------------------------------------
opencv_python_headless.libs         | 61.20 MB       
cv2                                 | 74.15 MB       
numpy.libs                          | 35.10 MB       
numpy                               | 20.45 MB       
onnxruntime                         | 19.30 MB       
pillow.libs                         | 16.20 MB       
PIL                                 | 2.30 MB        
------------------------------------------------------------
Total Layer Size: 244.10 MB / 250.00 MB
AWS Lambda Quota Utilization: 97.6%
SUCCESS: Layer is within AWS limits with headroom remaining.

Running verification smoke tests on stripped layer modules...
  [PASS] Successfully imported cv2 (v4.9.0)
  [PASS] Successfully imported PIL (v10.2.0)
  [PASS] Successfully imported numpy (v1.26.4)
  [PASS] Successfully imported onnxruntime (v1.16.3)
  [PASS] OpenCV image matrix Gaussian blur test succeeded (shape: (100, 100, 3))
  [PASS] ONNX Runtime execution engine initialized (providers: ['CPUExecutionProvider'])
All smoke tests passed cleanly without missing symbols!
```

### 3. Extract Zipped Layer for Deployment
```bash
make extract
```
This generates `layer.zip` ready for AWS CLI or Terraform:
```bash
aws lambda publish-layer-version \
    --layer-name cv-ml-inference-layer \
    --description "Pruned OpenCV Headless, ONNX Runtime, NumPy & Pillow layer" \
    --zip-file fileb://layer.zip \
    --compatible-runtimes python3.11 \
    --compatible-architectures x86_64
```

---

## 📖 Deep-Dive Architecture Article

For the complete technical breakdown of how ELF symbol stripping interacts with dynamic linkers (`glibc`/`musl`) and how to configure cross-account BuildKit caching, read the full engineering deep dive:

👉 **[Taming the 250MB AWS Lambda Limit: Dependency Surgery & BuildKit SSH Mounts](https://shivanshu27.github.io/my-personal-website/blog/taming-the-250mb-aws-lambda-limit/)**

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
