#!/bin/bash

# Test script for vLLM Multi-Model Gateway
# Tests all available model endpoints

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

GATEWAY_URL="${GATEWAY_URL:-https://localhost}"

echo "========================================="
echo "vLLM Multi-Model Gateway - Endpoint Tests"
echo "========================================="
echo ""
echo "Testing gateway at: $GATEWAY_URL"
echo ""

# Test 1: Health Check
echo -e "${BLUE}Test 1: Health Check${NC}"
if curl -k -s "$GATEWAY_URL/health" | grep -q "healthy"; then
    echo -e "${GREEN}✓ Health check passed${NC}"
else
    echo -e "${RED}✗ Health check failed${NC}"
    exit 1
fi
echo ""

# Test 2: List Models
echo -e "${BLUE}Test 2: List Available Models${NC}"
MODELS_RESPONSE=$(curl -k -s "$GATEWAY_URL/v1/models")
if echo "$MODELS_RESPONSE" | grep -q "gpt-oss"; then
    echo -e "${GREEN}✓ Model list endpoint working${NC}"
    echo "Available models:"
    echo "$MODELS_RESPONSE" | grep -o '"id": "[^"]*"' | sed 's/"id": "//g' | sed 's/"//g' | while read -r model; do
        echo "  • $model"
    done
else
    echo -e "${RED}✗ Model list endpoint failed${NC}"
    exit 1
fi
echo ""

# Function to test a model endpoint
test_model() {
    local MODEL_NAME=$1
    local MODEL_PATH=$2
    local ENDPOINT="$GATEWAY_URL/$MODEL_PATH/v1/chat/completions"

    echo -e "${BLUE}Test: $MODEL_NAME${NC}"
    echo "Endpoint: $ENDPOINT"

    # First check if the backend is reachable
    HEALTH_CHECK=$(curl -k -s -o /dev/null -w "%{http_code}" "$GATEWAY_URL/$MODEL_PATH/health" || echo "000")

    if [ "$HEALTH_CHECK" != "200" ]; then
        echo -e "${YELLOW}⚠ Model server not running or not ready (HTTP $HEALTH_CHECK)${NC}"
        echo "  This model may not be deployed or is still initializing."
        echo ""
        return 0
    fi

    # Make inference request
    RESPONSE=$(curl -k -s -w "\n%{http_code}" "$ENDPOINT" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "'"$MODEL_NAME"'",
            "messages": [
                {"role": "user", "content": "Say only the word: Hello"}
            ],
            "max_tokens": 10,
            "temperature": 0.0
        }' || echo "000")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" = "200" ]; then
        if echo "$BODY" | grep -q "choices"; then
            CONTENT=$(echo "$BODY" | grep -o '"content":"[^"]*"' | head -n1 | cut -d'"' -f4)
            echo -e "${GREEN}✓ Inference successful${NC}"
            echo "  Response: $CONTENT"
        else
            echo -e "${RED}✗ Unexpected response format${NC}"
            echo "  Response: $BODY"
        fi
    else
        echo -e "${RED}✗ Request failed (HTTP $HTTP_CODE)${NC}"
        echo "  Response: $BODY"
    fi
    echo ""
}

# Test 3: Check which models are actually running
echo -e "${BLUE}Detecting running model containers...${NC}"
RUNNING_MODELS=$(docker ps --format '{{.Names}}' | grep '^vllm-' || true)

if [ -z "$RUNNING_MODELS" ]; then
    echo -e "${YELLOW}⚠ No vLLM model containers found running${NC}"
    echo "Start models with: cd <model-dir> && docker compose up -d"
    echo ""
    exit 0
fi

echo "Running containers:"
echo "$RUNNING_MODELS" | while read -r container; do
    echo "  • $container"
done
echo ""

# Test each model if its container is running
echo "========================================="
echo "Testing Model Inference Endpoints"
echo "========================================="
echo ""

if echo "$RUNNING_MODELS" | grep -q "vllm-gpt-oss-120b"; then
    test_model "openai/gpt-oss-120b" "gpt-oss-120b"
fi

if echo "$RUNNING_MODELS" | grep -q "vllm-qwen-30b"; then
    test_model "Qwen/Qwen3-Coder-30B-A3B-Instruct" "qwen-30b"
fi

if echo "$RUNNING_MODELS" | grep -q "vllm-gpt-oss-20b"; then
    test_model "openai/gpt-oss-20b" "gpt-oss-20b"
fi

# Test 4: Streaming endpoint
echo -e "${BLUE}Test: Streaming Response${NC}"

# Find first running model for streaming test
if echo "$RUNNING_MODELS" | grep -q "vllm-gpt-oss-120b"; then
    STREAM_MODEL="gpt-oss-120b"
    STREAM_MODEL_NAME="openai/gpt-oss-120b"
elif echo "$RUNNING_MODELS" | grep -q "vllm-qwen-30b"; then
    STREAM_MODEL="qwen-30b"
    STREAM_MODEL_NAME="Qwen/Qwen3-Coder-30B-A3B-Instruct"
elif echo "$RUNNING_MODELS" | grep -q "vllm-gpt-oss-20b"; then
    STREAM_MODEL="gpt-oss-20b"
    STREAM_MODEL_NAME="openai/gpt-oss-20b"
else
    echo -e "${YELLOW}⚠ No models running for streaming test${NC}"
    echo ""
    exit 0
fi

echo "Using model: $STREAM_MODEL_NAME"
STREAM_RESPONSE=$(curl -k -s "$GATEWAY_URL/$STREAM_MODEL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{
        "model": "'"$STREAM_MODEL_NAME"'",
        "messages": [{"role": "user", "content": "Count to 3"}],
        "max_tokens": 20,
        "temperature": 0.0,
        "stream": true
    }' | head -c 200)

if echo "$STREAM_RESPONSE" | grep -q "data:"; then
    echo -e "${GREEN}✓ Streaming endpoint working${NC}"
    echo "  Sample stream output:"
    echo "$STREAM_RESPONSE" | head -n 3 | sed 's/^/  /'
else
    echo -e "${RED}✗ Streaming test failed${NC}"
fi
echo ""

# Summary
echo "========================================="
echo "Test Summary"
echo "========================================="
echo ""
echo "Gateway URL: $GATEWAY_URL"
echo "Running models: $(echo "$RUNNING_MODELS" | wc -l | tr -d ' ')"
echo ""
echo "For detailed logs, run:"
echo "  docker logs vllm-nginx-proxy"
echo ""
echo "To monitor GPU usage:"
echo "  nvidia-smi"
echo ""
