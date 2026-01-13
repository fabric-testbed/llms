#!/bin/bash

# LiteLLM Quick Start Script
# This script helps you quickly deploy LiteLLM proxy for vLLM models

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VLLM_DIR="$(dirname "$SCRIPT_DIR")"

echo "========================================"
echo "LiteLLM Proxy Quick Start"
echo "========================================"
echo ""

# Check if .env exists in parent directory
if [ ! -f "$VLLM_DIR/.env" ]; then
    echo "Error: .env file not found in $VLLM_DIR"
    echo "Please create .env from .env.example first:"
    echo "  cd $VLLM_DIR"
    echo "  cp .env.example .env"
    echo "  # Edit .env and set your configuration"
    exit 1
fi

# Source environment variables
echo "Loading environment variables from $VLLM_DIR/.env"
set -a
source "$VLLM_DIR/.env"
set +a

# Check for required variables
if [ -z "$LITELLM_MASTER_KEY" ] || [ "$LITELLM_MASTER_KEY" = "sk-1234-change-this-to-a-secure-key" ]; then
    echo "Warning: LITELLM_MASTER_KEY is not set or using default value"
    echo "Please update LITELLM_MASTER_KEY in $VLLM_DIR/.env"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if vllm_network exists
if ! docker network inspect vllm_network >/dev/null 2>&1; then
    echo "Error: vllm_network does not exist"
    echo "Please start at least one vLLM model server first:"
    echo "  cd $VLLM_DIR/gpt-oss-120b"
    echo "  docker compose up -d"
    exit 1
fi

# Check if vLLM model servers are running
echo ""
echo "Checking for running vLLM model servers..."
RUNNING_MODELS=0

if docker ps --format '{{.Names}}' | grep -q "vllm-gpt-oss-120b"; then
    echo "  ✓ vLLM GPT-OSS-120B is running"
    RUNNING_MODELS=$((RUNNING_MODELS + 1))
fi

if docker ps --format '{{.Names}}' | grep -q "vllm-gpt-oss-20b"; then
    echo "  ✓ vLLM GPT-OSS-20B is running"
    RUNNING_MODELS=$((RUNNING_MODELS + 1))
fi

if docker ps --format '{{.Names}}' | grep -q "vllm-qwen-30b"; then
    echo "  ✓ vLLM Qwen-30B is running"
    RUNNING_MODELS=$((RUNNING_MODELS + 1))
fi

if [ $RUNNING_MODELS -eq 0 ]; then
    echo ""
    echo "Error: No vLLM model servers are running"
    echo "Please start at least one model server first:"
    echo "  cd $VLLM_DIR/gpt-oss-120b && docker compose up -d"
    exit 1
fi

echo ""
echo "Found $RUNNING_MODELS running vLLM model server(s)"

# Start LiteLLM
echo ""
echo "Starting LiteLLM proxy and dependencies..."
cd "$SCRIPT_DIR"
docker compose up -d

echo ""
echo "Waiting for services to be healthy..."
sleep 5

# Check service health
echo ""
echo "Checking service health..."
for i in {1..30}; do
    if docker exec vllm-litellm-redis redis-cli ping >/dev/null 2>&1; then
        echo "  ✓ Redis is healthy"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "  ✗ Redis failed to start"
        exit 1
    fi
    sleep 1
done

for i in {1..30}; do
    if docker exec vllm-litellm-postgres pg_isready -U litellm >/dev/null 2>&1; then
        echo "  ✓ PostgreSQL is healthy"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "  ✗ PostgreSQL failed to start"
        exit 1
    fi
    sleep 1
done

for i in {1..60}; do
    if curl -s http://localhost:${LITELLM_PORT:-4000}/health >/dev/null 2>&1; then
        echo "  ✓ LiteLLM proxy is healthy"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "  ✗ LiteLLM proxy failed to start"
        echo "Check logs with: docker logs vllm-litellm-proxy"
        exit 1
    fi
    sleep 2
done

echo ""
echo "========================================"
echo "LiteLLM Proxy is ready!"
echo "========================================"
echo ""
echo "Proxy Endpoint:    http://localhost:${LITELLM_PORT:-4000}"
echo "Admin UI:          http://localhost:${LITELLM_PORT:-4000}/ui"
echo "API Key:           $LITELLM_MASTER_KEY"
echo ""
echo "Available Models:"
if docker ps --format '{{.Names}}' | grep -q "vllm-gpt-oss-120b"; then
    echo "  - gpt-oss-120b"
fi
if docker ps --format '{{.Names}}' | grep -q "vllm-gpt-oss-20b"; then
    echo "  - gpt-oss-20b"
fi
if docker ps --format '{{.Names}}' | grep -q "vllm-qwen-30b"; then
    echo "  - qwen-30b"
fi
echo ""
echo "Test the proxy:"
echo "  curl http://localhost:${LITELLM_PORT:-4000}/v1/models \\"
echo "    -H 'Authorization: Bearer $LITELLM_MASTER_KEY' | jq"
echo ""
echo "View logs:"
echo "  docker logs vllm-litellm-proxy -f"
echo ""
echo "Stop services:"
echo "  cd $SCRIPT_DIR && docker compose down"
echo "========================================"
