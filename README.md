# LLM Inference Services

This directory contains production-ready LLM inference deployments optimized for NVIDIA DGX Spark and multi-GPU VMs.

## Contents

### [vLLM Multi-Model Gateway](vllm/)

A production-ready multi-model inference gateway that runs multiple vLLM model servers behind an NGINX reverse proxy with HTTPS support.

**Features:**
- Multiple models served concurrently (GPT-OSS-20B, GPT-OSS-120B, Qwen-30B)
- Unified HTTPS endpoint with path-based routing
- OpenAI-compatible API
- Health monitoring and load balancing
- Support for both DGX Spark (UMA) and multi-GPU VMs

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  NGINX Gateway (HTTPS)                   │
│  Port 443 → Path-based routing to model servers         │
└─────────────────────────────────────────────────────────┘
                          │
      ┌───────────────────┼───────────────────┐
      │                   │                   │
┌─────▼─────┐   ┌─────────▼────────┐   ┌──────▼──────┐
│ GPT-OSS   │   │  GPT-OSS         │   │  Qwen-30B   │
│ 20B       │   │  120B            │   │  Coder      │
│ (1 GPU)   │   │  (3 GPUs)        │   │  (2 GPUs)   │
└───────────┘   └──────────────────┘   └─────────────┘
```

## Prerequisites

- **Hardware**: DGX Spark or multi-GPU VM (minimum 3 GPUs recommended)
- **Software**:
  - Docker & Docker Compose v2.0+
  - NVIDIA Container Toolkit
  - CUDA 13.0+
- **Access**: HuggingFace account with token for gated models

## Getting Started

1. **Navigate to vLLM directory:**
   ```bash
   cd llms/vllm/
   ```

2. **Follow the Quick Start guide:**
   - [Standard Deployment](vllm/README.md#quick-start) - for DGX Spark or single-model setups
   - [VM GPU Deployment](vllm/README.md#vm-deployment-with-dedicated-gpu-allocation) - for multi-model VMs

3. **Access the gateway:**
   ```bash
   curl -k https://localhost/v1/models
   ```

## Documentation

- **[vLLM Multi-Model Gateway Documentation](vllm/README.md)** - Complete setup, configuration, and usage guide
- **[vLLM Official Docs](https://docs.vllm.ai/)** - vLLM framework documentation
- **[OpenAI API Reference](https://platform.openai.com/docs/api-reference)** - API compatibility reference

## Support

For issues or questions:
- Check the [vLLM Troubleshooting Guide](vllm/README.md#troubleshooting)
- Review [vLLM GitHub Issues](https://github.com/vllm-project/vllm/issues)
- For DGX Spark specific issues, contact NVIDIA Enterprise Support