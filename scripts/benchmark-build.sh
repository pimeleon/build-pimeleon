#!/bin/bash
# benchmark-build.sh - Pimeleon Build System Benchmarking Wrapper
# Collects comprehensive build metrics and system information

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔬 Pimeleon Build System - Benchmarking Tool${NC}"
echo "=========================================================="

# Parse command line arguments
NO_CACHE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-cache)
            NO_CACHE=true
            echo -e "${YELLOW}⚡ No-cache benchmark mode enabled${NC}"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --no-cache       Run benchmark without APT cache for comparison"
            echo "  -h, --help       Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Create benchmark output directory
BENCHMARK_DIR="./benchmarks"
mkdir -p "$BENCHMARK_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
if [[ "$NO_CACHE" == "true" ]]; then
    BENCHMARK_FILE="$BENCHMARK_DIR/build-benchmark-nocache-$TIMESTAMP.json"
else
    BENCHMARK_FILE="$BENCHMARK_DIR/build-benchmark-$TIMESTAMP.json"
fi

# Function to collect system info
collect_system_info() {
    echo "Collecting system information..."

    # System specs
    local cpu_cores=$(nproc)
    local total_ram=$(free -m | awk '/^Mem:/{print $2}')
    local available_ram=$(free -m | awk '/^Mem:/{print $7}')
    local disk_space=$(df -BG / | tail -1 | awk '{print $2}' | sed 's/G//')
    local available_space=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')

    # Docker info
    local docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
    local docker_storage_driver=$(docker system info 2>/dev/null | grep "Storage Driver" | awk '{print $3}')

    # Build configuration
    local rpi_model=${RPI_MODEL:-3B+}
    local image_size=${IMAGE_SIZE:-4G}
    local raspbian_version=${RASPBIAN_VERSION:-buster}

    # Handle APT cache configuration
    local apt_cache_server="none"
    local apt_cache_available="false"

    if [[ "$NO_CACHE" == "true" ]]; then
        echo -e "${YELLOW}[BENCHMARK]${NC} Disabling APT cache for no-cache comparison"
        export APT_CACHE_SERVER=""
        apt_cache_server="disabled"
        apt_cache_available="false"
    else
        # Auto-detect or use provided APT cache server
        if [[ -z "${APT_CACHE_SERVER:-}" ]]; then
            # Try to auto-detect TrueNAS APT cache (TCP check)
            if timeout 1 bash -c "cat < /dev/null > /dev/tcp/192.168.76.5/3142" 2>/dev/null; then
                export APT_CACHE_SERVER=192.168.76.5
                export APT_CACHE_PORT=3142
                apt_cache_server="192.168.76.5:3142"
                apt_cache_available="true"
                echo -e "${GREEN}[BENCHMARK]${NC} Auto-detected TrueNAS APT cache: $apt_cache_server"
            else
                apt_cache_server="none"
                apt_cache_available="false"
                echo -e "${YELLOW}[BENCHMARK]${NC} No APT cache detected, using direct downloads"
            fi
        else
            apt_cache_server="${APT_CACHE_SERVER}:${APT_CACHE_PORT:-3142}"
            if timeout 1 bash -c "cat < /dev/null > /dev/tcp/${APT_CACHE_SERVER}/${APT_CACHE_PORT:-3142}" 2>/dev/null; then
                apt_cache_available="true"
                echo -e "${GREEN}[BENCHMARK]${NC} Using APT cache: $apt_cache_server"
            else
                apt_cache_available="false"
                echo -e "${RED}[BENCHMARK]${NC} APT cache server unreachable: $apt_cache_server"
            fi
        fi
    fi

    # System load before build
    local load_avg=$(cat /proc/loadavg | awk '{print $1}')

    cat > "$BENCHMARK_FILE" <<EOF
{
  "benchmark_info": {
    "timestamp": "$TIMESTAMP",
    "build_system_version": "v1.1.0-beta.1",
    "benchmark_tool_version": "1.0.0"
  },
  "system_specs": {
    "cpu_cores": $cpu_cores,
    "total_ram_mb": $total_ram,
    "available_ram_mb": $available_ram,
    "total_disk_gb": $disk_space,
    "available_disk_gb": $available_space,
    "load_average_pre_build": $load_avg
  },
  "docker_info": {
    "version": "$docker_version",
    "storage_driver": "$docker_storage_driver",
    "buildkit_enabled": true
  },
  "build_config": {
    "rpi_model": "$rpi_model",
    "image_size": "$image_size",
    "raspbian_version": "$raspbian_version",
    "apt_cache_server": "$apt_cache_server",
    "apt_cache_available": $apt_cache_available,
    "stages_enabled": ["stage1", "stage2"],
    "stages_disabled": ["stage3", "stage4"],
    "testing_mode": true,
    "no_cache_benchmark": $([ "$NO_CACHE" == "true" ] && echo "true" || echo "false")
  },
EOF
}

# Function to update benchmark with build results
finalize_benchmark() {
    local exit_code=$1
    local build_duration=$2
    local image_path=$3

    # System load after build
    local load_avg_post=$(cat /proc/loadavg | awk '{print $1}')
    local available_ram_post=$(free -m | awk '/^Mem:/{print $7}')
    local available_space_post=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')

    # Image info if successful
    local image_size_mb="null"
    local image_exists="false"
    if [[ -f "$image_path" ]]; then
        image_exists="true"
        image_size_mb=$(stat -c%s "$image_path" | awk '{print int($1/1024/1024)}')
    fi

    # Calculate cache effectiveness
    local cache_files=$(find ./cache -name "*.tar.gz" 2>/dev/null | wc -l)
    local cache_size_mb=0
    if [[ -d "./cache" ]]; then
        cache_size_mb=$(du -sm ./cache 2>/dev/null | awk '{print $1}' || echo 0)
    fi

    # Docker volumes usage
    local docker_volumes=$(docker volume ls --filter name=pimeleon-build --format "{{.Name}}" | wc -l)

    # Append build results to JSON
    cat >> "$BENCHMARK_FILE" <<EOF
  "build_results": {
    "exit_code": $exit_code,
    "duration_seconds": $build_duration,
    "success": $([ $exit_code -eq 0 ] && echo "true" || echo "false"),
    "image_generated": $image_exists,
    "image_size_mb": $image_size_mb
  },
  "performance_metrics": {
    "load_average_post_build": $load_avg_post,
    "available_ram_post_mb": $available_ram_post,
    "available_disk_post_gb": $available_space_post,
    "cache_files_count": $cache_files,
    "cache_size_mb": $cache_size_mb,
    "docker_volumes_count": $docker_volumes
  },
  "optimization_notes": [
    "Stages 3 and 4 disabled for testing",
    "APT cache server: $apt_cache_server",
    "Cache effectiveness: $([ $cache_files -gt 0 ] && echo "enabled" || echo "disabled")",
    "Benchmark mode: $([ "$NO_CACHE" == "true" ] && echo "no-cache comparison" || echo "optimized with cache")"
  ]
}
EOF

    echo -e "\n${GREEN}📊 Benchmark Results Summary:${NC}"
    echo "Duration: ${build_duration}s"
    echo "Exit Code: $exit_code"
    echo "Image Size: ${image_size_mb}MB"
    echo "Cache Files: $cache_files"
    echo "Full report: $BENCHMARK_FILE"
}

# Main execution
echo "Starting benchmark collection..."
collect_system_info

echo -e "\n${BLUE}🚀 Starting build process...${NC}"
START_TIME=$(date +%s)

# Run the actual build with fresh containers for accurate benchmarking
BUILD_EXIT_CODE=0
export DOCKER_BUILDKIT=1

echo -e "\n${BLUE}🏗️ Building containers without cache for accurate benchmarking...${NC}"
if [[ "$NO_CACHE" == "true" ]]; then
    # Build container with empty APT cache args to completely disable caching
    APT_CACHE_SERVER="" APT_CACHE_PORT="" docker compose build --no-cache builder >/dev/null 2>&1 || BUILD_EXIT_CODE=$?
else
    docker compose build --no-cache builder >/dev/null 2>&1 || BUILD_EXIT_CODE=$?
fi

if [[ $BUILD_EXIT_CODE -eq 0 ]]; then
    echo -e "\n${BLUE}🚀 Running Pimeleon image build...${NC}"
    docker compose run --rm builder >/dev/null 2>&1 || BUILD_EXIT_CODE=$?
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Find the generated image
IMAGE_PATH=$(find ./output -name "*.img" -type f | head -1)

echo -e "\n${BLUE}📋 Finalizing benchmark...${NC}"
finalize_benchmark $BUILD_EXIT_CODE $DURATION "$IMAGE_PATH"

if [[ $BUILD_EXIT_CODE -eq 0 ]]; then
    echo -e "\n${GREEN}✅ Build completed successfully!${NC}"
    echo -e "Build Duration: ${GREEN}${DURATION}s${NC}"
    if [[ -n "$IMAGE_PATH" ]]; then
        echo -e "Generated Image: ${GREEN}$(basename "$IMAGE_PATH")${NC}"
        echo -e "Image Size: ${GREEN}$(stat -c%s "$IMAGE_PATH" | awk '{print int($1/1024/1024)}')MB${NC}"
    fi
else
    echo -e "\n${RED}❌ Build failed with exit code: $BUILD_EXIT_CODE${NC}"
fi

echo -e "\n${BLUE}📊 Full benchmark report saved to: ${GREEN}$BENCHMARK_FILE${NC}"
echo -e "\n${YELLOW}💡 Next steps:${NC}"
echo "1. Review benchmark results in $BENCHMARK_FILE"
echo "2. If successful, flash image to SD card for hardware testing"
echo "3. Compare performance across different system configurations"
