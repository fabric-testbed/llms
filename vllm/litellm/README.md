# LiteLLM Proxy for vLLM Multi-Model Gateway

> Unified API gateway with load balancing, caching, and cost tracking for vLLM model servers

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Usage Examples](#usage-examples)
- [Advanced Features](#advanced-features)
- [Management](#management)
- [Troubleshooting](#troubleshooting)

---

## Overview

### What is this?

LiteLLM acts as a unified proxy layer for your vLLM model servers, providing:

- **Unified API**: Single endpoint for all models with OpenAI-compatible API
- **Load Balancing**: Distribute requests across multiple model instances
- **Request Caching**: Redis-based caching for repeated queries
- **Cost Tracking**: Monitor usage and costs per model/user
- **Rate Limiting**: Control request rates per API key
- **Fallback Support**: Automatic failover to backup models
- **Multi-Backend**: Easy integration with non-vLLM providers (OpenAI, Anthropic, etc.)
- **Admin UI**: Web-based dashboard for monitoring and configuration

### Architecture

```
┌──────────────────────────────────────────────────────────┐
│              LiteLLM Proxy (Port 4000)                   │
│  - Load Balancing                                        │
│  - Caching (Redis)                                       │
│  - Cost Tracking (PostgreSQL)                            │
│  - Rate Limiting                                         │
└──────────────────┬───────────────────────────────────────┘
                   │
    ┌──────────────┼──────────────┐
    │              │              │
┌───▼────┐  ┌──────▼─────┐  ┌────▼──────┐
│ GPT-   │  │  GPT-      │  │  Qwen-    │
│ OSS-   │  │  OSS-      │  │  30B      │
│ 120B   │  │  20B       │  │  :8000    │
│ :8000  │  │  :8000     │  │           │
└────────┘  └────────────┘  └───────────┘
```

### What to know before starting

- LiteLLM requires at least one vLLM model server to be running
- Redis is used for caching and load balancing state
- PostgreSQL is optional for persistent storage and analytics
- All services run in the same `vllm_network` as your vLLM servers

---

## Prerequisites

- **vLLM Model Servers**: At least one vLLM model container running
- **Docker Network**: `vllm_network` must exist (created by vLLM model servers)
- **Environment Variables**: `.env` file configured in parent `llms/vllm/` directory
- **Docker Compose**: v2.0+ installed

### Required Environment Variables

Ensure your `llms/vllm/.env` file contains:

```bash
# LiteLLM Configuration
LITELLM_MASTER_KEY=sk-your-secure-key-here  # Change from default!
LITELLM_UI_PASSWORD=admin
LITELLM_PORT=4000
LITELLM_REDIS_PORT=6379
LITELLM_POSTGRES_PORT=5432
LITELLM_POSTGRES_PASSWORD=litellm
```

---

## Quick Start

### Step 1: Ensure vLLM Models are Running

LiteLLM requires at least one vLLM model server to be active:

```bash
# Check running vLLM containers
docker ps | grep vllm

# If no models are running, start one:
cd ../gpt-oss-120b
docker compose up -d
```

### Step 2: Configure Environment Variables

If you haven't already, configure your environment:

```bash
cd ../../  # Go to llms/vllm/
cp .env.example .env
nano .env  # Edit and set LITELLM_MASTER_KEY
```

**Important**: Change `LITELLM_MASTER_KEY` from the default value!

### Step 3: Start LiteLLM

Use the quick-start script for automated deployment:

```bash
cd litellm
./quick-start.sh
```

Or manually:

```bash
cd litellm
docker compose up -d
```

### Step 4: Verify Deployment

```bash
# Check service health
curl http://localhost:4000/health

# List available models
curl http://localhost:4000/v1/models \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" | jq

# Access Admin UI
open http://localhost:4000/ui
```

---

## Configuration

### Model Configuration

Edit `config.yaml` to customize model settings:

```yaml
model_list:
  - model_name: gpt-oss-120b
    litellm_params:
      model: openai/gpt-oss-120b
      api_base: http://vllm-gpt-oss-120b:8000/v1
      api_key: "not-used"
      rpm: 100  # Requests per minute
      tpm: 100000  # Tokens per minute
```

### Load Balancing Strategies

Change `routing_strategy` in `config.yaml`:

- **simple-shuffle**: Random selection across available models
- **least-busy**: Route to model with fewest active requests
- **usage-based-routing-v2**: Route based on historical usage patterns

```yaml
router_settings:
  routing_strategy: least-busy  # Change this
  redis_host: redis
  redis_port: 6379
```

### Caching Configuration

Enable/disable caching in `config.yaml`:

```yaml
litellm_settings:
  cache: true  # Enable caching
  cache_type: redis  # Use Redis for cache
```

### Adding Custom Models

1. Edit `config.yaml` and add new model:

```yaml
model_list:
  - model_name: my-custom-model
    litellm_params:
      model: custom/model-name
      api_base: http://vllm-my-model:8000/v1
      api_key: "not-used"
```

2. Restart LiteLLM:

```bash
docker compose restart litellm
```

---

## Usage Examples

### List Available Models

```bash
curl http://localhost:4000/v1/models \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" | jq
```

### Chat Completion

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -d '{
    "model": "gpt-oss-120b",
    "messages": [
      {"role": "user", "content": "Explain quantum computing in one sentence"}
    ],
    "max_tokens": 100,
    "temperature": 0.7
  }' | jq
```

### Streaming Response

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -d '{
    "model": "qwen-30b",
    "messages": [
      {"role": "user", "content": "Write a Python function to calculate fibonacci"}
    ],
    "stream": true,
    "max_tokens": 200
  }'
```

### Python Client

```python
from openai import OpenAI

# Connect to LiteLLM proxy
client = OpenAI(
    base_url="http://localhost:4000/v1",
    api_key="sk-your-litellm-master-key",
)

# Make request
response = client.chat.completions.create(
    model="gpt-oss-120b",
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "Explain Docker in simple terms."}
    ],
    max_tokens=100,
    temperature=0.7
)

print(response.choices[0].message.content)
```

### Tool Calling

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:4000/v1",
    api_key="sk-your-litellm-master-key",
)

tools = [
    {
        "type": "function",
        "function": {
            "name": "get_weather",
            "description": "Get weather in a location",
            "parameters": {
                "type": "object",
                "properties": {
                    "location": {
                        "type": "string",
                        "description": "City and state, e.g. San Francisco, CA"
                    }
                },
                "required": ["location"]
            }
        }
    }
]

response = client.chat.completions.create(
    model="gpt-oss-120b",
    messages=[{"role": "user", "content": "What's the weather in Paris?"}],
    tools=tools,
    tool_choice="auto"
)

print(response.choices[0].message.tool_calls)
```

---

## Advanced Features

### Multiple Model Instances (Load Balancing)

Configure multiple instances of the same model for load balancing:

```yaml
model_list:
  # Instance 1
  - model_name: gpt-oss-120b
    litellm_params:
      model: openai/gpt-oss-120b
      api_base: http://vllm-gpt-oss-120b-1:8000/v1
      api_key: "not-used"

  # Instance 2
  - model_name: gpt-oss-120b
    litellm_params:
      model: openai/gpt-oss-120b
      api_base: http://vllm-gpt-oss-120b-2:8000/v1
      api_key: "not-used"

router_settings:
  routing_strategy: least-busy  # Route to least busy instance
```

### Fallback Configuration

Set up automatic fallback to smaller/faster models:

```yaml
model_list:
  # Primary: Large model
  - model_name: gpt-primary
    litellm_params:
      model: openai/gpt-oss-120b
      api_base: http://vllm-gpt-oss-120b:8000/v1
      api_key: "not-used"

  # Fallback: Smaller model (same model_name!)
  - model_name: gpt-primary
    litellm_params:
      model: openai/gpt-oss-20b
      api_base: http://vllm-gpt-oss-20b:8000/v1
      api_key: "not-used"

router_settings:
  num_retries: 2  # Try fallback on failure
  enable_pre_call_checks: true
```

### Cost Tracking

LiteLLM automatically tracks costs per model. View in Admin UI or query PostgreSQL:

```sql
-- Connect to PostgreSQL
docker exec -it vllm-litellm-postgres psql -U litellm

-- View usage by model
SELECT model, COUNT(*) as requests, SUM(response_cost) as total_cost
FROM litellm_spend
GROUP BY model;
```

### Rate Limiting per User

Configure per-user rate limits in `config.yaml`:

```yaml
general_settings:
  # Define rate limits per API key
  rate_limit_config:
    user-key-1:
      rpm: 100  # 100 requests per minute
      tpm: 10000  # 10k tokens per minute
    user-key-2:
      rpm: 500
      tpm: 50000
```

### Request Caching

LiteLLM caches identical requests automatically. Configure cache TTL:

```yaml
litellm_settings:
  cache: true
  cache_type: redis
  cache_kwargs:
    ttl: 3600  # Cache for 1 hour (seconds)
```

---

## Management

### View Logs

```bash
# LiteLLM proxy logs
docker logs vllm-litellm-proxy -f

# Redis logs
docker logs vllm-litellm-redis -f

# PostgreSQL logs
docker logs vllm-litellm-postgres -f
```

### Monitor Performance

```bash
# Check Redis cache statistics
docker exec vllm-litellm-redis redis-cli INFO stats

# View active connections
docker exec vllm-litellm-redis redis-cli CLIENT LIST

# Check PostgreSQL connections
docker exec vllm-litellm-postgres psql -U litellm -c "SELECT count(*) FROM pg_stat_activity;"
```

### Admin UI

Access the LiteLLM Admin UI at `http://localhost:4000/ui`:

- **Username**: `admin`
- **Password**: Set via `LITELLM_UI_PASSWORD` in `.env`

Features:
- View request logs
- Monitor costs per model
- Manage API keys
- View model health status
- Test models interactively

### Stop Services

```bash
# Graceful shutdown
docker compose down

# Force removal (including volumes)
docker compose down -v

# Stop specific service
docker stop vllm-litellm-proxy
```

### Restart Services

```bash
# Restart all services
docker compose restart

# Restart specific service
docker compose restart litellm
```

### Update Configuration

After editing `config.yaml`:

```bash
# Restart LiteLLM to apply changes
docker compose restart litellm

# Or recreate container
docker compose up -d --force-recreate litellm
```

---

## Troubleshooting

### Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Network vllm_network not found` | vLLM model servers not started | Start at least one vLLM model: `cd ../gpt-oss-120b && docker compose up -d` |
| `Connection refused` from LiteLLM | Model container hostname mismatch | Verify model container names match `config.yaml` api_base URLs |
| `401 Unauthorized` | Invalid API key | Check `Authorization: Bearer` header matches `LITELLM_MASTER_KEY` |
| `No models available` | All vLLM servers down | Verify vLLM containers are running: `docker ps | grep vllm` |
| Redis connection failed | Redis not started or unhealthy | Check Redis: `docker logs vllm-litellm-redis` |
| PostgreSQL connection failed | DB not ready | Wait for healthcheck: `docker ps` should show healthy status |
| High latency | No caching or too many requests | Enable Redis caching, increase `--num_workers` in docker-compose.yml |

### Health Checks

```bash
# Check LiteLLM health
curl http://localhost:4000/health

# Check Redis health
docker exec vllm-litellm-redis redis-cli ping

# Check PostgreSQL health
docker exec vllm-litellm-postgres pg_isready -U litellm

# Test model connectivity from LiteLLM
docker exec vllm-litellm-proxy curl http://vllm-gpt-oss-120b:8000/health
```

### Debug Mode

Enable detailed debugging by editing `docker-compose.yml`:

```yaml
environment:
  - LITELLM_LOG=DEBUG  # Change from INFO to DEBUG
```

Restart:
```bash
docker compose up -d --force-recreate litellm
docker logs vllm-litellm-proxy -f
```

### Clear Cache

```bash
# Clear Redis cache
docker exec vllm-litellm-redis redis-cli FLUSHALL

# Restart Redis
docker compose restart redis
```

### Reset Database

```bash
# Drop and recreate PostgreSQL database
docker compose down
docker volume rm litellm_postgres_data
docker compose up -d
```

---

## API Reference

### Endpoints

- `GET /health` - Health check
- `GET /v1/models` - List available models
- `POST /v1/chat/completions` - Chat completion (OpenAI-compatible)
- `POST /v1/completions` - Text completion
- `POST /v1/embeddings` - Generate embeddings
- `GET /ui` - Admin web interface
- `GET /metrics` - Prometheus metrics

### Authentication

All requests require the `Authorization` header:

```bash
Authorization: Bearer $LITELLM_MASTER_KEY
```

---

## Production Considerations

### Security

1. **Change default credentials**:
   - Set strong `LITELLM_MASTER_KEY`
   - Change `LITELLM_UI_PASSWORD`
   - Update PostgreSQL password

2. **Network isolation**:
   - Don't expose PostgreSQL/Redis ports externally
   - Use internal Docker network for backend communication

3. **HTTPS**:
   - Put LiteLLM behind NGINX with SSL/TLS
   - Use Let's Encrypt for production certificates

### Monitoring

- Enable Prometheus metrics endpoint
- Set up Grafana dashboards
- Configure alerting for failed requests
- Monitor Redis memory usage

### Scaling

- Increase `--num_workers` in docker-compose.yml
- Deploy multiple LiteLLM replicas behind load balancer
- Use external Redis cluster for shared state
- Consider managed PostgreSQL for analytics

---

## References

- [LiteLLM Documentation](https://docs.litellm.ai/)
- [LiteLLM GitHub](https://github.com/BerriAI/litellm)
- [OpenAI API Reference](https://platform.openai.com/docs/api-reference)
- [vLLM Documentation](https://docs.vllm.ai/)

---

## Support

For issues related to:
- **LiteLLM**: https://github.com/BerriAI/litellm/issues
- **vLLM Integration**: See parent directory README.md
- **DGX Spark**: Contact NVIDIA Enterprise Support
