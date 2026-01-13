#!/bin/bash

# LiteLLM Endpoint Testing Script
# Tests all LiteLLM proxy endpoints to verify functionality

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VLLM_DIR="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [ -f "$VLLM_DIR/.env" ]; then
    set -a
    source "$VLLM_DIR/.env"
    set +a
fi

LITELLM_URL="http://localhost:${LITELLM_PORT:-4000}"
API_KEY="${LITELLM_MASTER_KEY:-sk-1234}"

echo "========================================"
echo "LiteLLM Proxy Endpoint Tests"
echo "========================================"
echo ""
echo "LiteLLM URL: $LITELLM_URL"
echo "API Key: ${API_KEY:0:10}..."
echo ""

# Test 1: Health Check
echo "Test 1: Health Check"
echo "---------------------"
if curl -s "${LITELLM_URL}/health" | grep -q "healthy\|ok"; then
    echo "✓ Health check passed"
else
    echo "✗ Health check failed"
    exit 1
fi
echo ""

# Test 2: List Models
echo "Test 2: List Available Models"
echo "------------------------------"
MODELS_RESPONSE=$(curl -s "${LITELLM_URL}/v1/models" \
    -H "Authorization: Bearer ${API_KEY}")

if echo "$MODELS_RESPONSE" | jq -e '.data | length > 0' >/dev/null 2>&1; then
    echo "✓ Models endpoint working"
    echo ""
    echo "Available models:"
    echo "$MODELS_RESPONSE" | jq -r '.data[].id' | while read -r model; do
        echo "  - $model"
    done
else
    echo "✗ Failed to retrieve models"
    echo "Response: $MODELS_RESPONSE"
    exit 1
fi
echo ""

# Test 3: Chat Completion (first available model)
echo "Test 3: Chat Completion"
echo "-----------------------"
FIRST_MODEL=$(echo "$MODELS_RESPONSE" | jq -r '.data[0].id')
echo "Testing model: $FIRST_MODEL"

CHAT_RESPONSE=$(curl -s "${LITELLM_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${API_KEY}" \
    -d "{
        \"model\": \"${FIRST_MODEL}\",
        \"messages\": [{\"role\": \"user\", \"content\": \"Say 'LiteLLM test successful' and nothing else.\"}],
        \"max_tokens\": 20,
        \"temperature\": 0.1
    }")

if echo "$CHAT_RESPONSE" | jq -e '.choices[0].message.content' >/dev/null 2>&1; then
    echo "✓ Chat completion successful"
    echo ""
    echo "Response:"
    echo "$CHAT_RESPONSE" | jq -r '.choices[0].message.content'
else
    echo "✗ Chat completion failed"
    echo "Response: $CHAT_RESPONSE"
    exit 1
fi
echo ""

# Test 4: Streaming (if model supports it)
echo "Test 4: Streaming Response"
echo "--------------------------"
echo "Testing streaming with model: $FIRST_MODEL"

STREAM_OUTPUT=$(curl -s "${LITELLM_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${API_KEY}" \
    -d "{
        \"model\": \"${FIRST_MODEL}\",
        \"messages\": [{\"role\": \"user\", \"content\": \"Count to 3.\"}],
        \"stream\": true,
        \"max_tokens\": 20
    }" 2>&1)

if echo "$STREAM_OUTPUT" | grep -q "data:"; then
    echo "✓ Streaming response working"
    echo ""
    echo "First few chunks:"
    echo "$STREAM_OUTPUT" | head -n 5
else
    echo "✗ Streaming failed"
    echo "Output: $STREAM_OUTPUT"
fi
echo ""

# Test 5: Test each model individually
echo "Test 5: Test All Models Individually"
echo "-------------------------------------"

echo "$MODELS_RESPONSE" | jq -r '.data[].id' | while read -r model; do
    echo "Testing: $model"

    TEST_RESPONSE=$(curl -s "${LITELLM_URL}/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_KEY}" \
        -d "{
            \"model\": \"${model}\",
            \"messages\": [{\"role\": \"user\", \"content\": \"Hi\"}],
            \"max_tokens\": 5,
            \"temperature\": 0.1
        }")

    if echo "$TEST_RESPONSE" | jq -e '.choices[0].message.content' >/dev/null 2>&1; then
        echo "  ✓ $model is working"
    else
        echo "  ✗ $model failed"
        echo "  Response: $TEST_RESPONSE"
    fi
done
echo ""

# Test 6: Error Handling (invalid API key)
echo "Test 6: Authentication Error Handling"
echo "--------------------------------------"
ERROR_RESPONSE=$(curl -s "${LITELLM_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer invalid-key" \
    -d "{
        \"model\": \"${FIRST_MODEL}\",
        \"messages\": [{\"role\": \"user\", \"content\": \"Test\"}]
    }")

if echo "$ERROR_RESPONSE" | jq -e '.error' >/dev/null 2>&1; then
    echo "✓ Authentication error handling working correctly"
else
    echo "⚠ Warning: Authentication might not be enforced properly"
fi
echo ""

# Summary
echo "========================================"
echo "Test Summary"
echo "========================================"
echo ""
echo "✓ All critical tests passed!"
echo ""
echo "LiteLLM proxy is working correctly."
echo ""
echo "Next steps:"
echo "  1. Access Admin UI: ${LITELLM_URL}/ui"
echo "  2. View logs: docker logs vllm-litellm-proxy -f"
echo "  3. Monitor metrics: ${LITELLM_URL}/metrics"
echo ""
echo "For more usage examples, see README.md"
echo "========================================"
