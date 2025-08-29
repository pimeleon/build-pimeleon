#!/bin/bash
# clean-docker.sh - Selective Docker cleanup that preserves successful base image caches

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧹 Pi Router Build System - Selective Docker Cleanup${NC}"
echo "============================================================"

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we want to preserve caches
PRESERVE_CACHE=true
PRESERVE_VOLUMES=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --full)
            PRESERVE_CACHE=false
            PRESERVE_VOLUMES=false
            shift
            ;;
        --no-cache)
            PRESERVE_CACHE=false
            shift
            ;;
        --no-volumes)
            PRESERVE_VOLUMES=false
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --full        Full cleanup (removes everything including caches)"
            echo "  --no-cache    Remove local cache directory but keep Docker volumes"
            echo "  --no-volumes  Remove Docker volumes but keep local cache"
            echo "  -h, --help    Show this help message"
            echo ""
            echo "Default: Preserves successful base image caches and Docker volumes"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Get current disk usage
print_info "Checking disk space before cleanup..."
BEFORE_SPACE=$(df -h / | tail -1 | awk '{print $4}')
echo "Available space: $BEFORE_SPACE"

# Stop Docker Compose services
print_info "Stopping Docker Compose services..."
docker compose down 2>/dev/null || true

# List cache status before cleanup
if [[ "$PRESERVE_CACHE" == "true" ]]; then
    print_info "Checking cache status..."
    if [[ -d "./cache" ]]; then
        echo "Local cache directory contents:"
        ls -lah ./cache/ 2>/dev/null || echo "  (empty or no access)"
    fi
fi

# Backup cache if preserving and it exists
TEMP_CACHE_DIR=""
if [[ "$PRESERVE_CACHE" == "true" ]] && [[ -d "./cache" ]] && [[ -n "$(ls -A ./cache 2>/dev/null)" ]]; then
    TEMP_CACHE_DIR=$(mktemp -d)
    print_info "Backing up cache directory to $TEMP_CACHE_DIR"
    cp -r ./cache/* "$TEMP_CACHE_DIR/" 2>/dev/null || true
fi

# Cleanup Docker containers and images
print_info "Removing Docker containers, images, and networks..."
docker system prune -af

# Cleanup build cache
print_info "Clearing Docker build cache..."
docker builder prune -af

# Handle volumes
if [[ "$PRESERVE_VOLUMES" == "true" ]]; then
    print_warning "Preserving Docker volumes (apt-cache, debootstrap-cache, pip-cache)"
    # Only remove orphaned volumes, not our named ones
    docker volume prune -f
else
    print_warning "Removing all Docker volumes including caches"
    docker system prune -af --volumes
fi

# Handle local cache directory
if [[ "$PRESERVE_CACHE" == "false" ]]; then
    print_warning "Removing local cache directory"
    rm -rf ./cache
    mkdir -p ./cache
else
    print_info "Preserving local cache directory"
fi

# Restore cache if we backed it up
if [[ -n "$TEMP_CACHE_DIR" ]] && [[ "$PRESERVE_CACHE" == "true" ]]; then
    print_info "Restoring cache directory"
    mkdir -p ./cache
    cp -r "$TEMP_CACHE_DIR"/* ./cache/ 2>/dev/null || true
    rm -rf "$TEMP_CACHE_DIR"
fi

# Check space after cleanup
print_info "Checking disk space after cleanup..."
AFTER_SPACE=$(df -h / | tail -1 | awk '{print $4}')
echo "Available space: $AFTER_SPACE (was: $BEFORE_SPACE)"

print_success "Selective cleanup completed!"

# Show preserved resources
echo ""
echo -e "${GREEN}📦 Preserved Resources:${NC}"
if [[ "$PRESERVE_CACHE" == "true" ]]; then
    echo "✅ Local cache directory (./cache) - contains successful base images"
else
    echo "❌ Local cache directory removed"
fi

if [[ "$PRESERVE_VOLUMES" == "true" ]]; then
    echo "✅ Docker volumes preserved:"
    docker volume ls --filter name=pi-router-build 2>/dev/null || echo "  (no volumes found)"
else
    echo "❌ All Docker volumes removed"
fi

echo ""
echo -e "${BLUE}🚀 Next Steps:${NC}"
echo "1. Rebuild containers: APT_CACHE_SERVER=192.168.76.5 docker compose build --no-cache builder"
echo "2. Run build: APT_CACHE_SERVER=192.168.76.5 docker compose --progress quiet run --rm builder"
echo ""
echo "Or use the full command with cache server detection:"
echo 'if ping -c1 192.168.76.5 &>/dev/null; then export APT_CACHE_SERVER=192.168.76.5; fi && docker compose build --no-cache builder'