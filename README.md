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

## 📏 Results (measured in CI on every push)

| | Size |
|---|---:|
| After `pip install`, before surgery | **494 MB** |
| After dependency surgery | **230 MB** (229.63 MiB by the verifier, 91.9% of quota) |
| Shared libraries stripped | 67 |
| Gate | the build **fails** if the layer exceeds 250 MiB |

The gate has fired for real: one build came out at **252.82 MB** (2.82 MB over),
because transitive documentation packages (sympy, pygments, docutils) leaked in.
Adding them to the surgery list fixed it, and later CI size tables exposed
`_pytest` and `snowballstemmer`, which were pruned the same way.

> **About the "280 MB → 148 MB" figure in the blog post:** that is a production
> migration at work, on a different stack (PyTorch, OpenCV and internal
> libraries). This repository applies the same technique to a public
> inference stack, so its numbers differ; the table above is what anyone can
> reproduce.

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

Real output, copied from the CI run that verifies every push (Lambda Python 3.11 image, x86_64):
```text
Analyzing layer footprint at: /opt/python
------------------------------------------------------------
Package / Item                      | Size           
------------------------------------------------------------
cv2                                 | 71.88 MB       
opencv_python_headless.libs         | 60.30 MB       
numpy.libs                          | 34.90 MB       
numpy                               | 20.81 MB       
onnxruntime                         | 17.18 MB       
pillow.libs                         | 15.43 MB       
PIL                                 | 1.99 MB        
google                              | 1.24 MB        
charset_normalizer                  | 643.72 KB      
yaml                                | 572.78 KB      
------------------------------------------------------------
Total Layer Size: 229.63 MB / 250.00 MB
AWS Lambda Quota Utilization: 91.9%
SUCCESS: Layer is within AWS limits with 20.37 MB headroom remaining.
Running verification smoke tests on stripped layer modules...
  [PASS] Successfully imported cv2 (v4.9.0)
  [PASS] Successfully imported PIL (v12.2.0)
  [PASS] Successfully imported numpy (v1.26.4)
  [PASS] Successfully imported onnxruntime (v1.16.3)
  [PASS] OpenCV image matrix Gaussian blur test succeeded (shape: (100, 100, 3))
  [PASS] ONNX Runtime execution engine initialized (providers: ['AzureExecutionProvider', 'CPUExecutionProvider'])
All smoke tests passed cleanly without missing symbols!
```
(`MB` in the verifier is MiB: the limit it checks is 250 × 1024 × 1024 = 262,144,000 bytes, exactly AWS's number.)

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
