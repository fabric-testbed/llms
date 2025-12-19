# Multi-Model vLLM Gateway with NGINX

> Deploy multiple vLLM model servers behind a unified HTTPS gateway with NVIDIA DGX Spark

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Usage Examples](#usage-examples)
- [Management](#management)
- [Troubleshooting](#troubleshooting)

---

## Overview

### What is this?

This setup provides a production-ready multi-model inference gateway that runs multiple vLLM model servers behind an NGINX reverse proxy. Each model runs in its own container with dedicated resources, while NGINX provides:

- **Unified HTTPS endpoint** with self-signed certificates
- **Path-based routing** to different models (`/gpt-oss-20b`, `/gpt-oss-120b`, `/qwen-30b`)
- **Load balancing** with connection keepalive
- **Health checks** and monitoring
- **Streaming optimization** for real-time inference

### What you'll accomplish

- Deploy multiple LLM inference servers concurrently on DGX Spark
- Configure HTTPS access with SSL/TLS certificates
- Route requests to different models through a single gateway endpoint
- Monitor and manage multiple model servers from a unified interface

### What to know before starting

- Experience with Docker Compose for multi-container applications
- Understanding of NGINX reverse proxy configuration
- Familiarity with OpenAI-compatible API endpoints
- Knowledge of SSL/TLS certificates (self-signed and production)
- Experience with environment variable configuration

## Prerequisites

- **DGX Spark** with Blackwell GPU architecture (128GB unified memory)
- **Docker** installed and configured: `docker --version` succeeds
- **Docker Compose** v2.0+: `docker compose version` succeeds
- **NVIDIA Container Toolkit** installed
- **HuggingFace account** with access tokens for gated models
- **Network access** to pull container images and models
- **Sufficient GPU memory** for running multiple models concurrently

### GPU Memory Planning

Approximate memory requirements per model:
- **GPT-OSS-20B**: ~20GB GPU memory
- **GPT-OSS-120B**: ~60GB GPU memory (with FP8 KV cache)
- **Qwen-30B**: ~30GB GPU memory (with FP8 KV cache)

DGX Spark's 128GB unified memory allows running 1-2 large models or 2-3 smaller models concurrently.

## Time & Risk

- **Duration**: 15-20 minutes for initial setup
- **Risks**: Minimal - all services run in isolated containers
- **Rollback**: Simple container removal, no system-level changes
- **Last Updated**: 2025-12-19

---

## Architecture

### Component Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     NGINX Gateway                           │
│  HTTPS (443) / HTTP (80) → Redirect to HTTPS               │
│  - /gpt-oss-20b/   → vllm-gpt-oss-20b:8000                 │
│  - /gpt-oss-120b/  → vllm-gpt-oss-120b:8000                │
│  - /qwen-30b/      → vllm-qwen-30b:8000                     │
└─────────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
┌───────▼──────┐  ┌─────────▼────────┐  ┌──────▼────────┐
│ vLLM Server  │  │  vLLM Server     │  │ vLLM Server   │
│ GPT-OSS-20B  │  │  GPT-OSS-120B    │  │  Qwen-30B     │
│ Port: 8001   │  │  Port: 8002      │  │  Port: 8003   │
│ Container:   │  │  Container:      │  │  Container:   │
│ GPU access   │  │  GPU access      │  │  GPU access   │
└──────────────┘  └──────────────────┘  └───────────────┘
```

### Network Architecture

All containers join the `vllm_network` bridge network, allowing:
- Inter-container communication by hostname
- NGINX to proxy requests to backend vLLM servers
- Shared HuggingFace model cache across containers

### File Structure

```
llms/vllm/
├── README.md                    # This file
├── docker-compose.yml           # NGINX gateway configuration
├── certs.sh                     # SSL certificate generation script
├── quick-start.sh               # Interactive deployment script
├── shutdown.sh                  # Graceful shutdown script
├── test-endpoints.sh            # Endpoint testing script
├── .env.example                 # Environment variable template
├── ssl/                         # Generated SSL certificates (gitignored)
│   ├── public.pem              # Self-signed certificate
│   └── private.pem             # Private key
├── nginx/
│   └── multi-model.conf        # NGINX routing configuration
├── gpt-oss-20b/
│   ├── docker-compose.yml      # GPT-OSS-20B vLLM server
│   └── chat.template           # Chat template for GPT-OSS models
├── gpt-oss-120b/
│   ├── docker-compose.yml      # GPT-OSS-120B vLLM server
│   └── chat.template           # Chat template for GPT-OSS models
└── qwen-30b/
    ├── docker-compose.yml      # Qwen-30B vLLM server
    └── chat.template           # Chat template for Qwen models
```

---

## Quick Start

### Step 1. Generate SSL Certificates

Create self-signed certificates for HTTPS access:

```bash
cd llms/vllm
./certs.sh
```

This creates `ssl/public.pem` and `ssl/private.pem` with 10-year validity for localhost.

**For production**: Replace self-signed certificates with CA-issued certificates:
```bash
# Replace generated files with your production certificates
cp /path/to/your/cert.pem ssl/public.pem
cp /path/to/your/key.pem ssl/private.pem
```

### Step 2. Configure HuggingFace Authentication

Set your HuggingFace token for downloading gated models:

```bash
export HF_TOKEN=your_hf_token_here
```

Or create a `.env` file:
```bash
# llms/vllm/.env
HF_TOKEN=your_hf_token_here
VLLM_LOGGING_LEVEL=INFO
NGINX_HTTPS_PORT=443
NGINX_HTTP_PORT=80
```

### Step 3. Start Model Servers

Launch the models you want to deploy. You can start all three or select individual models based on memory requirements.

**Option A: Start all models** (requires ~110GB+ GPU memory):
```bash
cd llms/vllm/gpt-oss-20b && docker compose up -d
cd ../gpt-oss-120b && docker compose up -d
cd ../qwen-30b && docker compose up -d
```

**Option B: Start specific models**:
```bash
# Start only GPT-OSS-120B (recommended for most use cases)
cd llms/vllm/gpt-oss-120b
docker compose up -d
```

### Step 4. Start NGINX Gateway

After model servers are running:

```bash
cd llms/vllm
docker compose up -d
```

### Step 5. Verify Deployment

Check all services are healthy:

```bash
# Check all running containers
docker ps

# Check NGINX logs
docker logs vllm-nginx-proxy

# Verify health endpoint
curl -k https://localhost/health
```

Expected output: `healthy`

### Step 6. Test Model Inference

Test the gateway with a sample request:

```bash
# Quick test all endpoints
./test-endpoints.sh

# Or manually test GPT-OSS-120B
curl -k https://localhost/gpt-oss-120b/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/gpt-oss-120b",
    "messages": [{"role": "user", "content": "Explain quantum computing in one sentence."}],
    "max_tokens": 100,
    "temperature": 0.7
  }'
```

### Step 7. Shutdown (When Done)

Gracefully stop all services:

```bash
# Graceful shutdown (recommended)
./shutdown.sh

# Force shutdown (removes containers)
./shutdown.sh --force

# Remove everything including cached models (WARNING: requires re-download)
./shutdown.sh --force --remove-volumes
```

---

## Configuration

### Model-Specific Settings

Each model directory contains a `docker-compose.yml` with model-specific configuration:

#### GPT-OSS-120B Configuration

Located in `gpt-oss-120b/docker-compose.yml`:

```yaml
command: >
  vllm serve openai/gpt-oss-120b
    --enable-auto-tool-choice      # Enable automatic tool selection
    --tool-call-parser openai      # Use OpenAI tool call format
    --chat-template /root/chat.template
    --tensor-parallel-size 1       # Single GPU (change for multi-GPU)
    --max-model-len 4096          # Maximum context length
    --kv-cache-dtype fp8          # Use FP8 for KV cache compression
    --trust-remote-code           # Allow remote code execution
```

**Key parameters to adjust:**
- `--max-model-len`: Reduce if memory constrained (default: 4096)
- `--tensor-parallel-size`: Increase for multi-GPU setups
- `--kv-cache-dtype`: Options are `auto`, `fp8`, `fp16` (FP8 saves ~50% memory)
- `--gpu-memory-utilization`: Default 0.9, increase to 0.95 for maximum throughput

#### Qwen-30B Configuration

Located in `qwen-30b/docker-compose.yml`:

```yaml
command: >
  vllm serve Qwen/Qwen3-Coder-30B-A3B-Instruct
    --enable-auto-tool-choice
    --tool-call-parser qwen3_code  # Qwen-specific parser
    --chat-template /root/chat.template
    --tensor-parallel-size 1
    --max-model-len 8192          # Higher context for code tasks
    --kv-cache-dtype fp8
    --trust-remote-code
```

### NGINX Configuration

The NGINX configuration (`nginx/multi-model.conf`) provides:

#### Path-based Routing

```nginx
# Route pattern: /<model-name>/<api-path>
location /gpt-oss-120b/ {
    rewrite ^/gpt-oss-120b/(.*) /$1 break;  # Strip prefix
    proxy_pass http://gpt-oss-120b-backend;
}
```

#### Streaming Optimization

```nginx
proxy_buffering off;           # Disable buffering for streaming
proxy_cache off;               # No caching for real-time responses
proxy_http_version 1.1;        # HTTP/1.1 for keepalive
proxy_set_header Connection "";# Persistent connections
```

#### Timeout Settings

Default timeouts are set to 30 minutes (1800 seconds) to accommodate:
- Long-running tool-calling sequences
- Complex reasoning tasks
- Large context processing

```nginx
proxy_read_timeout 1800;
proxy_connect_timeout 1800;
proxy_send_timeout 1800;
```

### Environment Variables

Create `.env` file in `llms/vllm/` directory:

```bash
# Required
HF_TOKEN=your_huggingface_token

# Optional - NGINX ports
NGINX_HTTPS_PORT=443
NGINX_HTTP_PORT=80

# Optional - vLLM logging
VLLM_LOGGING_LEVEL=INFO  # Options: DEBUG, INFO, WARNING, ERROR

# Optional - vLLM optimizations (set in docker-compose.yml)
CUDA_MANAGED_FORCE_DEVICE_ALLOC=1
PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
VLLM_USE_V1=1  # Enable vLLM v1 engine
```

### GPU Assignment

By default, all models use all available GPUs. To assign specific GPUs:

Edit the model's `docker-compose.yml`:

```yaml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          device_ids: ['0']  # Uncomment and specify GPU ID
          capabilities: [gpu]
```

---

## Usage Examples

### List Available Models

```bash
curl -k https://localhost/v1/models | jq
```

Response:
```json
{
  "object": "list",
  "data": [
    {
      "id": "gpt-oss-20b",
      "object": "model",
      "endpoint": "/gpt-oss-20b/v1/chat/completions"
    },
    {
      "id": "gpt-oss-120b",
      "object": "model",
      "endpoint": "/gpt-oss-120b/v1/chat/completions"
    },
    {
      "id": "qwen-30b",
      "object": "model",
      "endpoint": "/qwen-30b/v1/chat/completions"
    }
  ]
}
```

### Chat Completion

```bash
curl -k https://localhost/gpt-oss-120b/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/gpt-oss-120b",
    "messages": [
      {"role": "system", "content": "You are a helpful AI assistant."},
      {"role": "user", "content": "What is the capital of France?"}
    ],
    "max_tokens": 50,
    "temperature": 0.7
  }' | jq .
```

### Streaming Response

```bash
curl -k https://localhost/qwen-30b/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-Coder-30B-A3B-Instruct",
    "messages": [
      {"role": "user", "content": "Write a Python function to calculate fibonacci numbers."}
    ],
    "stream": true,
    "max_tokens": 200
  }'
```

### Tool Calling (Function Calling)

```bash
curl -k https://localhost/gpt-oss-120b/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/gpt-oss-120b",
    "messages": [
      {"role": "user", "content": "What is the weather in San Francisco?"}
    ],
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "get_weather",
          "description": "Get the current weather in a location",
          "parameters": {
            "type": "object",
            "properties": {
              "location": {
                "type": "string",
                "description": "The city and state, e.g. San Francisco, CA"
              },
              "unit": {
                "type": "string",
                "enum": ["celsius", "fahrenheit"]
              }
            },
            "required": ["location"]
          }
        }
      }
    ],
    "tool_choice": "auto"
  }' | jq .
```

### Python Client Example

```python
from openai import OpenAI

# Configure client to use local gateway
client = OpenAI(
    base_url="https://localhost/gpt-oss-120b/v1",
    api_key="not-used",  # vLLM doesn't require API key
)

# Disable SSL verification for self-signed certificates
import httpx
client._client = httpx.Client(verify=False)

# Make request
response = client.chat.completions.create(
    model="openai/gpt-oss-120b",
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "Explain Docker in simple terms."}
    ],
    max_tokens=100,
    temperature=0.7
)

print(response.choices[0].message.content)
```

### Using Different Models

Switch models by changing the path prefix:

```python
# Use GPT-OSS-120B (best for reasoning and tool calling)
client_120b = OpenAI(base_url="https://localhost/gpt-oss-120b/v1", api_key="not-used")

# Use Qwen-30B (best for code generation)
client_qwen = OpenAI(base_url="https://localhost/qwen-30b/v1", api_key="not-used")

# Use GPT-OSS-20B (fastest, smaller model)
client_20b = OpenAI(base_url="https://localhost/gpt-oss-20b/v1", api_key="not-used")
```

---

## Management

### View Logs

```bash
# NGINX gateway logs
docker logs vllm-nginx-proxy -f

# Model server logs
docker logs vllm-gpt-oss-120b -f
docker logs vllm-qwen-30b -f
docker logs vllm-gpt-oss-20b -f
```

### Monitor Resource Usage

```bash
# GPU memory usage
nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv

# Container resource usage
docker stats

# Detailed GPU metrics per container
docker exec vllm-gpt-oss-120b nvidia-smi
```

### Stop Services

```bash
# Recommended: Use the shutdown script for graceful shutdown
./shutdown.sh

# Force shutdown (removes containers)
./shutdown.sh --force

# Manual shutdown if needed
cd llms/vllm
docker compose down
cd gpt-oss-120b && docker compose down
cd ../qwen-30b && docker compose down
cd ../gpt-oss-20b && docker compose down

# Or stop specific services
docker stop vllm-nginx-proxy
docker stop vllm-gpt-oss-120b
```

### Restart Services

```bash
# Restart NGINX (for config changes)
docker restart vllm-nginx-proxy

# Restart model server
docker restart vllm-gpt-oss-120b
```

### Update Model Configuration

1. Edit the model's `docker-compose.yml`
2. Recreate the container:

```bash
cd llms/vllm/gpt-oss-120b
docker compose up -d --force-recreate
```

### Add New Model

1. Create new model directory:

```bash
mkdir llms/vllm/my-model
cp llms/vllm/gpt-oss-120b/docker-compose.yml llms/vllm/my-model/
```

2. Edit `llms/vllm/my-model/docker-compose.yml`:
   - Change container name
   - Update port mapping
   - Modify vLLM serve command with new model

3. Add upstream and location to `nginx/multi-model.conf`:

```nginx
upstream my-model-backend {
    server vllm-my-model:8000;
    keepalive 32;
}

location /my-model/ {
    rewrite ^/my-model/(.*) /$1 break;
    proxy_pass http://my-model-backend;
    # ... (copy other proxy settings)
}
```

4. Update model list in NGINX config endpoints

5. Restart services:

```bash
cd llms/vllm/my-model && docker compose up -d
cd .. && docker compose restart
```

---

## Troubleshooting

### Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `curl: (60) SSL certificate problem` | Self-signed certificate not trusted | Use `-k` flag with curl, or install certificate in system trust store |
| `502 Bad Gateway` from NGINX | Backend vLLM server not running | Check `docker ps`, verify model container is running and healthy |
| `504 Gateway Timeout` | Model loading or inference taking too long | Increase NGINX timeout in `multi-model.conf`, check vLLM logs for errors |
| `CUDA Out of Memory` | Multiple large models exceeding GPU capacity | Stop some models, reduce `--max-model-len`, or use `--kv-cache-dtype fp8` |
| `Network vllm_network not found` | Model containers not started first | Start at least one model container before starting NGINX |
| `Cannot access gated repo` | HuggingFace token invalid or missing | Set `HF_TOKEN` environment variable, regenerate token if expired |
| Container fails to start | Port already in use | Change port mapping in docker-compose.yml or stop conflicting service |
| Model download fails | Network issues or authentication | Verify `HF_TOKEN`, check internet connectivity, use `huggingface-cli login` |

### Memory Management

DGX Spark uses Unified Memory Architecture (UMA). If encountering memory issues:

```bash
# Flush buffer cache
sudo sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'

# Check actual memory usage
free -h
nvidia-smi
```

### Health Check Debugging

```bash
# Check NGINX health
curl -k https://localhost/health

# Check individual model server health
curl http://localhost:8001/health  # GPT-OSS-20B direct port
curl http://localhost:8002/health  # GPT-OSS-120B direct port
curl http://localhost:8003/health  # Qwen-30B direct port

# Check from inside NGINX container
docker exec vllm-nginx-proxy wget -O- http://vllm-gpt-oss-120b:8000/health
```

### View Container Details

```bash
# Inspect NGINX configuration
docker exec vllm-nginx-proxy cat /etc/nginx/conf.d/default.conf

# Check NGINX error logs
docker exec vllm-nginx-proxy cat /var/log/nginx/error.log

# Verify network connectivity
docker exec vllm-nginx-proxy ping vllm-gpt-oss-120b
```

### Certificate Issues

If HTTPS is not working:

```bash
# Verify certificates exist
ls -la llms/vllm/ssl/

# Regenerate certificates
cd llms/vllm
./certs.sh

# Check certificate details
openssl x509 -in ssl/public.pem -text -noout

# Restart NGINX to reload certificates
docker restart vllm-nginx-proxy
```

### Performance Tuning

For optimal performance:

1. **Memory optimization**: Use FP8 KV cache (`--kv-cache-dtype fp8`)
2. **Context length**: Set `--max-model-len` based on your needs (lower = more memory for batching)
3. **GPU utilization**: Increase `--gpu-memory-utilization` to 0.95 for maximum throughput
4. **Batching**: Adjust `--max-num-batched-tokens` for your workload
5. **Connection pooling**: NGINX keepalive already configured (32 connections per backend)

---

## Production Deployment Considerations

### Security

- **Replace self-signed certificates** with CA-issued certificates from Let's Encrypt or your organization
- **Add authentication** using NGINX auth_basic or integrate with OAuth/OIDC
- **Firewall rules**: Restrict access to port 443/80 to authorized networks
- **Secrets management**: Use Docker secrets or external secret management (e.g., Vault)

### Monitoring

- **Metrics collection**: Integrate with Prometheus for vLLM metrics
- **Log aggregation**: Ship NGINX and vLLM logs to centralized logging (e.g., ELK stack)
- **Alerting**: Configure alerts for health check failures, high latency, or OOM errors

### High Availability

- **Load balancing**: Deploy multiple DGX Spark nodes behind a load balancer
- **Health checks**: Configure upstreams to mark failed backends as down
- **Graceful shutdown**: Use `docker compose stop` to allow in-flight requests to complete

### Model Updates

- **Blue-green deployment**: Start new model version on different port, update NGINX config, then stop old version
- **Rolling updates**: Update models one at a time to maintain availability
- **Model versioning**: Use explicit model version tags in HuggingFace paths

---

## References

- [vLLM Documentation](https://docs.vllm.ai/)
- [NGINX Reverse Proxy Guide](https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/)
- [Docker Compose Networking](https://docs.docker.com/compose/networking/)
- [HuggingFace Model Hub](https://huggingface.co/models)
- [OpenAI API Reference](https://platform.openai.com/docs/api-reference)

---

## Support

For issues related to:
- **vLLM**: https://github.com/vllm-project/vllm/issues
- **NGINX**: https://nginx.org/en/docs/
- **DGX Spark**: Contact NVIDIA Enterprise Support
