.PHONY: help build build-ab2p build-app build-all build-local build-docker test clean lint dev shell docs check-deps list-apps version next-version

# Default app (can be overridden: make build TARGET_PLATFORM=rpi4-bookworm)
TARGET_PLATFORM ?= rpi3-bookworm
PROFILE ?= development

# Default target
help:
	@echo "Pimeleon Build System (Monorepo)"
	@echo "================================="
	@echo ""
	@echo "Build targets:"
	@echo "  make build TARGET_PLATFORM=<app>   - Build specified app (default: $(TARGET_PLATFORM))"
	@echo "  make build-all         - Build all apps"
	@echo "  make build-prod        - Build with production profile"
	@echo "  make list-apps         - List available apps"
	@echo "  make check-deps        - Check local build dependencies"
	@echo ""
	@echo "Test targets:"
	@echo "  make test TARGET_PLATFORM=<app>    - Run all tests for app"
	@echo "  make test-smoke        - Run smoke tests only"
	@echo ""
	@echo "Development:"
	@echo "  make dev               - Start development environment"
	@echo "  make shell             - Open shell in builder container"
	@echo "  make lint              - Run linters"
	@echo "  make clean             - Clean build artifacts"
	@echo ""
	@echo "Available apps:"
	@for app in apps/*/; do \
		[ -d "$$app" ] && echo "  - $$(basename $$app)"; \
	done
	@echo ""
	@echo "Examples:"
	@echo "  make build TARGET_PLATFORM=rpi3-bookworm"
	@echo "  make build TARGET_PLATFORM=rpi4-bookworm PROFILE=production"
	@echo ""

# List available apps
list-apps:
	@echo "Available apps:"
	@echo "==============="
	@for app in apps/*/; do \
		[ -d "$$app" ] || continue; \
		name=$$(basename $$app); \
		device=$${name%%-*}; \
		debian=$${name##*-}; \
		printf "  %-20s (%s, %s)\n" "$$name" "$$device" "$$debian"; \
	done

# Build targets
build: build-docker

# Build adblock2privoxy image if missing (dependency for builder)
build-ab2p:
	@if ! docker image inspect pimeleon-adblock2privoxy:latest >/dev/null 2>&1; then \
		echo "Building adblock2privoxy image (one-time)..."; \
		./scripts/build-ab2p.sh; \
	fi

build-docker: build-ab2p
	@echo "Building app: $(TARGET_PLATFORM)"
	@if [ ! -d "apps/$(TARGET_PLATFORM)" ]; then \
		echo "Error: App '$(TARGET_PLATFORM)' not found"; \
		echo ""; \
		$(MAKE) list-apps; \
		exit 1; \
	fi
	TARGET_PLATFORM=$(TARGET_PLATFORM) PIMELEON_PROFILE=$(PROFILE) docker compose run --rm builder

build-all:
	@echo "Building all apps..."
	@for app in apps/*/; do \
		[ -d "$$app" ] || continue; \
		appname=$$(basename $$app); \
		echo ""; \
		echo "========================================"; \
		echo "Building $$appname..."; \
		echo "========================================"; \
		$(MAKE) build TARGET_PLATFORM=$$appname || exit 1; \
	done
	@echo ""
	@echo "All apps built successfully!"

build-prod:
	@echo "Building production image for $(TARGET_PLATFORM)..."
	$(MAKE) build PROFILE=production

build-dev:
	@echo "Building development image for $(TARGET_PLATFORM)..."
	$(MAKE) build PROFILE=development

build-nocache: build-ab2p
	@echo "Building $(TARGET_PLATFORM) (no cache)..."
	docker compose build --no-cache builder
	TARGET_PLATFORM=$(TARGET_PLATFORM) PIMELEON_PROFILE=$(PROFILE) docker compose run --rm builder

build-local: check-deps
	@echo "Building Pimeleon image (local)..."
	sudo TARGET_PLATFORM=$(TARGET_PLATFORM) ./shared/scripts/build.sh

check-deps:
	@echo "Checking local build dependencies..."
	@./scripts/check-local-deps.sh 2>/dev/null || echo "Local deps check script not found"

# Test targets
test: build
	@echo "Running full test suite for $(TARGET_PLATFORM)..."
	docker compose build tester
	TARGET_PLATFORM=$(TARGET_PLATFORM) docker compose run --rm -e TEST_SUITE=all tester

test-smoke:
	@echo "Running smoke tests for $(TARGET_PLATFORM)..."
	docker compose build tester
	TARGET_PLATFORM=$(TARGET_PLATFORM) docker compose run --rm -e TEST_SUITE=smoke tester

test-integration:
	@echo "Running integration tests for $(TARGET_PLATFORM)..."
	docker compose build tester
	TARGET_PLATFORM=$(TARGET_PLATFORM) docker compose run --rm -e TEST_SUITE=integration tester

test-security:
	@echo "Running security tests for $(TARGET_PLATFORM)..."
	docker compose build tester
	TARGET_PLATFORM=$(TARGET_PLATFORM) docker compose run --rm -e TEST_SUITE=security tester

# Development targets
dev:
	@echo "Starting development environment..."
	docker compose up -d dev
	@echo "Development environment is ready. Use 'make shell' to enter."

shell:
	@echo "Opening shell in builder container for $(TARGET_PLATFORM)..."
	TARGET_PLATFORM=$(TARGET_PLATFORM) docker compose run --rm builder bash

# Linting targets
lint: lint-yaml lint-shell lint-ansible

lint-yaml:
	@echo "Linting YAML files..."
	@docker run --rm -v $(PWD):/workspace cytopia/yamllint -c .yamllint . 2>/dev/null || echo "yamllint not available"

lint-shell:
	@echo "Linting shell scripts..."
	@docker run --rm -v $(PWD):/workspace koalaman/shellcheck-alpine \
		find /workspace/shared/scripts -name "*.sh" -type f -exec shellcheck {} \; 2>/dev/null || echo "shellcheck not available"

lint-ansible:
	@echo "Linting Ansible playbooks..."
	@docker run --rm -v $(PWD):/workspace \
		cytopia/ansible-lint shared/ansible/playbooks/*.yml 2>/dev/null || echo "ansible-lint not available"

lint-docker:
	@echo "Linting Dockerfiles..."
	@docker run --rm -i hadolint/hadolint < shared/containers/builder/Dockerfile 2>/dev/null || echo "hadolint not available"

# Documentation
docs:
	@echo "Building documentation..."
	@mkdir -p docs
	@echo "Documentation targets not yet configured for monorepo"

# Cleanup targets
clean:
	@echo "Cleaning build artifacts..."
	rm -rf output/*.img output/*.tar.gz output/pimeleon-*
	rm -rf tests/results/*
	docker compose down -v 2>/dev/null || true

clean-cache:
	@echo "Cleaning build cache..."
	rm -rf cache/*

clean-all: clean clean-cache
	@echo "Removing all containers and images..."
	docker compose down -v --rmi all 2>/dev/null || true

# Utility targets
logs:
	docker compose logs -f

ps:
	docker compose ps

# CI/CD simulation
ci-local:
	@echo "Running local CI pipeline for $(TARGET_PLATFORM)..."
	$(MAKE) lint
	$(MAKE) build TARGET_PLATFORM=$(TARGET_PLATFORM)
	$(MAKE) test-smoke TARGET_PLATFORM=$(TARGET_PLATFORM)
	@echo "Local CI pipeline completed!"

# Version information
version:
	@echo "Pimeleon Build System v2.0.0 (Monorepo)"
	@echo ""
	@echo "Next image version for $(TARGET_PLATFORM):"
	@./shared/scripts/get-next-version.sh $(TARGET_PLATFORM)
	@echo ""
	@echo "Docker version:"
	@docker --version
	@echo "Docker Compose version:"
	@docker compose version

# Show only the calculated next version (for scripting)
next-version:
	@./shared/scripts/get-next-version.sh $(TARGET_PLATFORM)
