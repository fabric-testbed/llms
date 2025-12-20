#!/bin/bash

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================="
echo "vLLM Multi-Model Gateway - Quick Start"
echo "========================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed${NC}"
    exit 1
fi

if ! command -v docker compose &> /dev/null; then
    echo -e "${RED}Error: Docker Compose is not installed${NC}"
    exit 1
fi

if ! command -v nvidia-smi &> /dev/null; then
    echo -e "${RED}Error: nvidia-smi not found. Is NVIDIA driver installed?${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites check passed${NC}"
echo ""

# Check for .env file and HF_TOKEN
if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        echo -e "${YELLOW}No .env file found. Creating from .env.example...${NC}"
        cp .env.example .env
        echo -e "${GREEN}✓ Created .env file${NC}"
        echo ""
        echo -e "${YELLOW}IMPORTANT: Edit .env and set your HF_TOKEN${NC}"
        echo "  1. Get token from: https://huggingface.co/settings/tokens"
        echo "  2. Edit llms/vllm/.env and set HF_TOKEN=your_token_here"
        echo "  3. Run this script again"
        echo ""
        exit 1
    fi
fi

# Load environment variables
if [ -f ".env" ]; then
    source .env
fi

# Check for HF_TOKEN
if [ -z "$HF_TOKEN" ]; then
    echo -e "${YELLOW}Warning: HF_TOKEN not set in .env${NC}"
    echo "Some models may require HuggingFace authentication."
    echo ""
    echo "To set it:"
    echo "  1. Get token from: https://huggingface.co/settings/tokens"
    echo "  2. Edit llms/vllm/.env and set HF_TOKEN=your_token_here"
    echo "  OR: export HF_TOKEN=your_token_here"
    echo ""
    read -p "Continue without HF_TOKEN? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Sync environment variables to model directories
echo "Syncing environment variables to model directories..."
./sync-env.sh
echo ""

# Generate SSL certificates if they don't exist
if [ ! -f "ssl/public.pem" ] || [ ! -f "ssl/private.pem" ]; then
    echo "Generating SSL certificates..."
    ./certs.sh
    echo ""
else
    echo -e "${GREEN}✓ SSL certificates already exist${NC}"
    echo ""
fi

# Check available GPU memory
echo "Checking GPU memory..."
GPU_MEM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n1)
GPU_FREE=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | head -n1)

echo "Total GPU Memory: ${GPU_MEM}MB"
echo "Free GPU Memory: ${GPU_FREE}MB"
echo ""

# Model selection
echo "Select models to deploy:"
echo ""
echo "  1) GPT-OSS-120B only (recommended, ~60GB)"
echo "  2) Qwen-30B only (~30GB)"
echo "  3) GPT-OSS-20B only (~20GB)"
echo "  4) GPT-OSS-120B + GPT-OSS-20B (~80GB)"
echo "  5) All models (~110GB, requires sufficient memory)"
echo "  6) Custom selection"
echo ""

read -p "Choose option [1-6]: " OPTION

START_120B=false
START_30B=false
START_20B=false

case $OPTION in
    1)
        START_120B=true
        ;;
    2)
        START_30B=true
        ;;
    3)
        START_20B=true
        ;;
    4)
        START_120B=true
        START_20B=true
        ;;
    5)
        START_120B=true
        START_30B=true
        START_20B=true
        ;;
    6)
        read -p "Start GPT-OSS-120B? [y/N] " -n 1 -r; echo
        [[ $REPLY =~ ^[Yy]$ ]] && START_120B=true

        read -p "Start Qwen-30B? [y/N] " -n 1 -r; echo
        [[ $REPLY =~ ^[Yy]$ ]] && START_30B=true

        read -p "Start GPT-OSS-20B? [y/N] " -n 1 -r; echo
        [[ $REPLY =~ ^[Yy]$ ]] && START_20B=true
        ;;
    *)
        echo -e "${RED}Invalid option${NC}"
        exit 1
        ;;
esac

# Verify at least one model selected
if ! $START_120B && ! $START_30B && ! $START_20B; then
    echo -e "${RED}Error: No models selected${NC}"
    exit 1
fi

echo ""
echo "Starting model servers..."
echo ""

# Start selected models
if $START_120B; then
    echo "Starting GPT-OSS-120B..."
    cd gpt-oss-120b
    docker compose up -d
    cd ..
    echo -e "${GREEN}✓ GPT-OSS-120B started${NC}"
fi

if $START_30B; then
    echo "Starting Qwen-30B..."
    cd qwen-30b
    docker compose up -d
    cd ..
    echo -e "${GREEN}✓ Qwen-30B started${NC}"
fi

if $START_20B; then
    echo "Starting GPT-OSS-20B..."
    cd gpt-oss-20b
    docker compose up -d
    cd ..
    echo -e "${GREEN}✓ GPT-OSS-20B started${NC}"
fi

echo ""
echo "Waiting for model servers to initialize (this may take 2-5 minutes)..."
echo "Model loading progress can be monitored with: docker logs -f <container-name>"
echo ""

# Wait a bit for containers to start
sleep 5

# Start NGINX gateway
echo "Starting NGINX gateway..."
docker compose up -d
echo -e "${GREEN}✓ NGINX gateway started${NC}"
echo ""

# Wait for services to be ready
echo "Waiting for services to be healthy..."
MAX_WAIT=180  # 3 minutes
WAITED=0

while [ $WAITED -lt $MAX_WAIT ]; do
    if curl -k -s https://localhost/health > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Services are healthy${NC}"
        break
    fi
    sleep 5
    WAITED=$((WAITED + 5))
    echo -n "."
done

echo ""
echo ""

if [ $WAITED -ge $MAX_WAIT ]; then
    echo -e "${YELLOW}Warning: Health check timeout. Services may still be initializing.${NC}"
    echo "Check logs with: docker logs vllm-nginx-proxy"
else
    echo "========================================="
    echo "  Deployment Complete!"
    echo "========================================="
fi

echo ""
echo "Access your models at:"
echo ""

if $START_120B; then
    echo "  • GPT-OSS-120B:  https://localhost/gpt-oss-120b/v1/chat/completions"
fi

if $START_30B; then
    echo "  • Qwen-30B:      https://localhost/qwen-30b/v1/chat/completions"
fi

if $START_20B; then
    echo "  • GPT-OSS-20B:   https://localhost/gpt-oss-20b/v1/chat/completions"
fi

echo ""
echo "Gateway endpoints:"
echo "  • Health check:  https://localhost/health"
echo "  • Model list:    https://localhost/v1/models"
echo ""
echo "Useful commands:"
echo "  • View logs:     docker logs -f vllm-nginx-proxy"
echo "  • Stop services: docker compose down && cd gpt-oss-*/qwen-*/gpt-oss-* && docker compose down"
echo "  • GPU usage:     nvidia-smi"
echo ""
echo "For detailed documentation, see README.md"
echo ""
