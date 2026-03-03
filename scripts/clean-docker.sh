#!/bin/bash
# clean-docker.sh - Selective Docker cleanup that preserves successful base image caches

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧹 Pimeleon Build System - Selective Docker Cleanup${NC}"
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
CLEAN_OUTPUT=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --full)
            PRESERVE_CACHE=false
            PRESERVE_VOLUMES=false
            CLEAN_OUTPUT=true
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
        --clean-output)
            CLEAN_OUTPUT=true
            shift
            ;;
        --keep-output)
            CLEAN_OUTPUT=false
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --full           Full cleanup (removes everything including caches and old outputs)"
            echo "  --no-cache       Remove local cache directory but keep Docker volumes"
            echo "  --no-volumes     Remove Docker volumes but keep local cache"
            echo "  --clean-output   Clean old image files and logs from output directory (default)"
            echo "  --keep-output    Preserve all image files and logs in output directory"
            echo "  -h, --help       Show this help message"
            echo ""
            echo "Default: Preserves successful base image caches and Docker volumes, but cleans old outputs"
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
    # Use rsync if available for more reliable copy, fallback to cp
    if command -v rsync &>/dev/null; then
        rsync -a ./cache/ "$TEMP_CACHE_DIR/"
    else
        cp -a ./cache/. "$TEMP_CACHE_DIR/"
    fi
fi

# Cleanup Docker resources (granularly to avoid stalls and provide feedback)
print_info "Removing stopped Docker containers..."
docker container prune -f

print_info "Removing unused Docker networks..."
docker network prune -f

print_info "Removing unused Docker images (preserving adblock2privoxy)..."
# Keep pimeleon-adblock2privoxy:latest if it exists
docker image prune -f --filter "label!=com.pimeleon.image=adblock2privoxy"

# Cleanup build cache
print_info "Clearing Docker build cache..."
docker builder prune -af

# Handle volumes
if [[ "$PRESERVE_VOLUMES" == "true" ]]; then
    print_warning "Preserving Docker volumes (apt-cache, debootstrap-cache, pip-cache)"
    # Only remove orphaned volumes
    print_info "Removing orphaned volumes..."
    docker volume prune -f
else
    print_warning "Removing all Docker volumes including caches"
    docker volume prune -af
fi

# Handle local cache directory
if [[ "$PRESERVE_CACHE" == "false" ]]; then
    print_warning "Removing local cache directory"
    sudo rm -rf ./cache
    mkdir -p ./cache
else
    print_info "Preserving local cache directory"
fi

# Restore cache if we backed it up
if [[ -n "$TEMP_CACHE_DIR" ]] && [[ "$PRESERVE_CACHE" == "true" ]]; then
    print_info "Restoring cache directory"
    mkdir -p ./cache
    if command -v rsync &>/dev/null; then
        rsync -a "$TEMP_CACHE_DIR/" ./cache/
    else
        cp -a "$TEMP_CACHE_DIR"/. ./cache/
    fi
    rm -rf "$TEMP_CACHE_DIR"
fi

# Reload cached images if missing
if [[ -f "./cache/pimeleon-adblock2privoxy.tar.gz" ]]; then
    if ! docker image inspect pimeleon-adblock2privoxy:latest &>/dev/null; then
        print_info "Reloading adblock2privoxy image from cache..."
        zcat "./cache/pimeleon-adblock2privoxy.tar.gz" | docker load
    else
        print_info "adblock2privoxy image already exists, skipping reload"
    fi
fi

# Handle output directory cleanup
if [[ "$CLEAN_OUTPUT" == "true" ]] && [[ -d "./output" ]]; then
    print_info "Cleaning output directory..."

    # Count files before cleanup
    IMG_COUNT=$(find ./output -name "*.img" -type f | wc -l 2>/dev/null || echo "0")
    LOG_COUNT=$(find ./output -name "build-*.log" -type f | wc -l 2>/dev/null || echo "0")

    if [[ $IMG_COUNT -gt 0 ]] || [[ $LOG_COUNT -gt 0 ]]; then
        echo "Found $IMG_COUNT image files and $LOG_COUNT log files"

        # Keep only the most recent image and its log
        LATEST_IMG=$(find ./output -name "*.img" -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
        if [[ -n "$LATEST_IMG" ]]; then
            LATEST_BASENAME=$(basename "$LATEST_IMG" .img)
            LATEST_LOG="./output/build-${LATEST_BASENAME#pimeleon-}.log"

            print_warning "Preserving latest image: $(basename "$LATEST_IMG")"
            if [[ -f "$LATEST_LOG" ]]; then
                print_warning "Preserving latest log: $(basename "$LATEST_LOG")"
            fi

            # Remove old images (keep latest)
            find ./output -name "*.img" -type f ! -path "$LATEST_IMG" -delete 2>/dev/null || true

            # Remove old logs (keep latest and password file)
            find ./output -name "build-*.log" -type f ! -path "$LATEST_LOG" -delete 2>/dev/null || true
        else
            # No images found, remove all logs
            find ./output -name "build-*.log" -type f -delete 2>/dev/null || true
        fi

        # Count files after cleanup
        REMAINING_IMG=$(find ./output -name "*.img" -type f | wc -l 2>/dev/null || echo "0")
        REMAINING_LOG=$(find ./output -name "build-*.log" -type f | wc -l 2>/dev/null || echo "0")

        REMOVED_IMG=$((IMG_COUNT - REMAINING_IMG))
        REMOVED_LOG=$((LOG_COUNT - REMAINING_LOG))

        print_success "Removed $REMOVED_IMG old images and $REMOVED_LOG old logs"
        echo "Kept: $REMAINING_IMG image(s), $REMAINING_LOG log(s), and pi-initial-password.txt"
    else
        print_info "Output directory is already clean (no .img or .log files found)"
    fi
else
    if [[ "$CLEAN_OUTPUT" == "false" ]]; then
        print_info "Preserving all output files"
    fi
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
    docker volume ls --filter name=pimeleon-build 2>/dev/null || echo "  (no volumes found)"
else
    echo "❌ All Docker volumes removed"
fi

if [[ "$CLEAN_OUTPUT" == "false" ]]; then
    echo "✅ Output directory preserved - all images and logs kept"
else
    echo "🧹 Output directory cleaned - kept latest image, log, and password file"
fi

# Show if adblock2privoxy was found and preserved
if docker image inspect pimeleon-adblock2privoxy:latest &>/dev/null; then
    echo "✅ Docker image preserved: pimeleon-adblock2privoxy:latest"
fi

echo -e "${BLUE}🚀 Next Steps:${NC}"
echo "1. Rebuild containers: APT_CACHE_SERVER=192.168.76.5 docker compose build --no-cache builder"
echo "2. Run build: TARGET_PLATFORM=rpi3-bookworm make build"
echo ""
echo "Or use the full command with cache server detection:"
echo 'if timeout 1 bash -c "cat < /dev/null > /dev/tcp/192.168.76.5/3142" &>/dev/null; then export APT_CACHE_SERVER=192.168.76.5; fi && docker compose build --no-cache builder'
