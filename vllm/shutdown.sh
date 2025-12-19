#!/bin/bash

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================="
echo "vLLM Multi-Model Gateway - Shutdown"
echo "========================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse command line arguments
REMOVE_VOLUMES=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --remove-volumes|-v)
            REMOVE_VOLUMES=true
            shift
            ;;
        --force|-f)
            FORCE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -f, --force           Force stop containers (docker compose down)"
            echo "  -v, --remove-volumes  Remove volumes (WARNING: deletes cached models)"
            echo "  -h, --help           Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                    # Graceful shutdown (recommended)"
            echo "  $0 --force            # Force shutdown"
            echo "  $0 --remove-volumes   # Remove containers and volumes"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check what's currently running
echo "Checking running services..."
echo ""

NGINX_RUNNING=false
MODEL_120B_RUNNING=false
MODEL_30B_RUNNING=false
MODEL_20B_RUNNING=false

if docker ps --format '{{.Names}}' | grep -q '^vllm-nginx-proxy$'; then
    NGINX_RUNNING=true
    echo -e "${BLUE}  • NGINX Gateway (vllm-nginx-proxy)${NC}"
fi

if docker ps --format '{{.Names}}' | grep -q '^vllm-gpt-oss-120b$'; then
    MODEL_120B_RUNNING=true
    echo -e "${BLUE}  • GPT-OSS-120B (vllm-gpt-oss-120b)${NC}"
fi

if docker ps --format '{{.Names}}' | grep -q '^vllm-qwen-30b$'; then
    MODEL_30B_RUNNING=true
    echo -e "${BLUE}  • Qwen-30B (vllm-qwen-30b)${NC}"
fi

if docker ps --format '{{.Names}}' | grep -q '^vllm-gpt-oss-20b$'; then
    MODEL_20B_RUNNING=true
    echo -e "${BLUE}  • GPT-OSS-20B (vllm-gpt-oss-20b)${NC}"
fi

if ! $NGINX_RUNNING && ! $MODEL_120B_RUNNING && ! $MODEL_30B_RUNNING && ! $MODEL_20B_RUNNING; then
    echo -e "${YELLOW}No vLLM services are currently running${NC}"
    exit 0
fi

echo ""

# Confirm shutdown
if ! $FORCE; then
    echo -e "${YELLOW}This will stop all running vLLM services.${NC}"
    if $REMOVE_VOLUMES; then
        echo -e "${RED}WARNING: --remove-volumes will delete HuggingFace model cache!${NC}"
        echo -e "${RED}You will need to re-download models on next startup.${NC}"
    fi
    echo ""
    read -p "Continue with shutdown? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Shutdown cancelled"
        exit 0
    fi
    echo ""
fi

# Function to check if any containers are still processing requests
check_active_connections() {
    if $NGINX_RUNNING; then
        ACTIVE=$(docker exec vllm-nginx-proxy sh -c 'cat /var/log/nginx/access.log 2>/dev/null | tail -n 1' 2>/dev/null || echo "")
        if [ -n "$ACTIVE" ]; then
            echo -e "${YELLOW}Note: Recent activity detected in NGINX logs${NC}"
        fi
    fi
}

# Shutdown sequence
echo "========================================="
echo "Shutting down services..."
echo "========================================="
echo ""

# Step 1: Stop NGINX gateway first (prevents new requests)
if $NGINX_RUNNING; then
    echo -e "${BLUE}[1/4]${NC} Stopping NGINX Gateway..."
    check_active_connections

    if $FORCE; then
        docker compose down ${REMOVE_VOLUMES:+--volumes} 2>/dev/null || true
    else
        docker compose stop 2>/dev/null || true
    fi

    if ! docker ps --format '{{.Names}}' | grep -q '^vllm-nginx-proxy$'; then
        echo -e "${GREEN}  ✓ NGINX Gateway stopped${NC}"
    else
        echo -e "${YELLOW}  ⚠ NGINX Gateway still running (may be processing requests)${NC}"
    fi
    echo ""
else
    echo -e "${BLUE}[1/4]${NC} NGINX Gateway not running, skipping..."
    echo ""
fi

# Step 2: Wait a moment for in-flight requests to complete
if ! $FORCE && ($MODEL_120B_RUNNING || $MODEL_30B_RUNNING || $MODEL_20B_RUNNING); then
    echo -e "${BLUE}[2/4]${NC} Waiting for in-flight requests to complete (5 seconds)..."
    sleep 5
    echo -e "${GREEN}  ✓ Grace period complete${NC}"
    echo ""
else
    echo -e "${BLUE}[2/4]${NC} Skipping grace period..."
    echo ""
fi

# Step 3: Stop model servers
echo -e "${BLUE}[3/4]${NC} Stopping model servers..."
echo ""

MODELS_STOPPED=0

if $MODEL_120B_RUNNING; then
    echo "  Stopping GPT-OSS-120B..."
    cd gpt-oss-120b
    if $FORCE; then
        docker compose down ${REMOVE_VOLUMES:+--volumes} 2>/dev/null || true
    else
        docker compose stop 2>/dev/null || true
    fi
    cd ..

    if ! docker ps --format '{{.Names}}' | grep -q '^vllm-gpt-oss-120b$'; then
        echo -e "${GREEN}  ✓ GPT-OSS-120B stopped${NC}"
        ((MODELS_STOPPED++))
    fi
fi

if $MODEL_30B_RUNNING; then
    echo "  Stopping Qwen-30B..."
    cd qwen-30b
    if $FORCE; then
        docker compose down ${REMOVE_VOLUMES:+--volumes} 2>/dev/null || true
    else
        docker compose stop 2>/dev/null || true
    fi
    cd ..

    if ! docker ps --format '{{.Names}}' | grep -q '^vllm-qwen-30b$'; then
        echo -e "${GREEN}  ✓ Qwen-30B stopped${NC}"
        ((MODELS_STOPPED++))
    fi
fi

if $MODEL_20B_RUNNING; then
    echo "  Stopping GPT-OSS-20B..."
    cd gpt-oss-20b
    if $FORCE; then
        docker compose down ${REMOVE_VOLUMES:+--volumes} 2>/dev/null || true
    else
        docker compose stop 2>/dev/null || true
    fi
    cd ..

    if ! docker ps --format '{{.Names}}' | grep -q '^vllm-gpt-oss-20b$'; then
        echo -e "${GREEN}  ✓ GPT-OSS-20B stopped${NC}"
        ((MODELS_STOPPED++))
    fi
fi

echo ""

# Step 4: Cleanup (if requested)
if $FORCE || $REMOVE_VOLUMES; then
    echo -e "${BLUE}[4/4]${NC} Cleaning up..."

    # Remove stopped containers
    STOPPED_CONTAINERS=$(docker ps -a --format '{{.Names}}' | grep '^vllm-' || true)
    if [ -n "$STOPPED_CONTAINERS" ]; then
        echo "  Removing stopped containers..."
        echo "$STOPPED_CONTAINERS" | xargs -r docker rm -f 2>/dev/null || true
        echo -e "${GREEN}  ✓ Containers removed${NC}"
    fi

    if $REMOVE_VOLUMES; then
        echo ""
        echo -e "${YELLOW}  Removing volumes (HuggingFace cache will be deleted)...${NC}"
        docker volume ls --format '{{.Name}}' | grep -E '^(gpt-oss-|qwen-)' | xargs -r docker volume rm 2>/dev/null || true
        echo -e "${GREEN}  ✓ Volumes removed${NC}"
    fi
    echo ""
else
    echo -e "${BLUE}[4/4]${NC} Keeping stopped containers (use --force to remove)"
    echo ""
fi

# Final status
echo "========================================="
echo "Shutdown Complete"
echo "========================================="
echo ""
echo -e "${GREEN}Successfully stopped $MODELS_STOPPED model server(s)${NC}"

if ! $FORCE; then
    echo ""
    echo "Containers are stopped but not removed."
    echo "To restart: ./quick-start.sh"
    echo "To remove containers: docker compose down && cd <model-dir> && docker compose down"
    echo "To force shutdown: ./shutdown.sh --force"
fi

if $REMOVE_VOLUMES; then
    echo ""
    echo -e "${YELLOW}Volumes were removed. Models will be re-downloaded on next startup.${NC}"
fi

# Show GPU status
echo ""
echo "Current GPU status:"
nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv,noheader | \
    awk -F', ' '{printf "  GPU %s (%s): %s / %s\n", $1, $2, $3, $4}'

echo ""
echo "For more information, see README.md"
echo ""
