.PHONY: help build build-local build-docker test clean lint dev shell docs check-deps

# Default target
help:
	@echo "Pimeleon Build System"
	@echo "====================="
	@echo ""
	@echo "Build targets:"
	@echo "  make build         - Build image (Docker, default)"
	@echo "  make build-local   - Build image locally (faster, requires deps)"
	@echo "  make build-docker  - Build image in Docker container"
	@echo "  make build-prod    - Production build (Docker)"
	@echo "  make check-deps    - Check local build dependencies"
	@echo ""
	@echo "Test targets:"
	@echo "  make test          - Run all tests"
	@echo "  make test-smoke    - Run smoke tests only"
	@echo ""
	@echo "Development:"
	@echo "  make dev           - Start development environment"
	@echo "  make shell         - Open shell in builder container"
	@echo "  make lint          - Run linters"
	@echo "  make clean         - Clean build artifacts"
	@echo ""

# Build targets
build: build-docker

build-docker:
	@echo "Building Pimeleon image (Docker)..."
	docker compose build builder
	docker compose run --rm builder

build-local: check-deps
	@echo "Building Pimeleon image (local)..."
	sudo ./scripts/build-local.sh

build-prod:
	@echo "Building production Pimeleon image..."
	PIMELEON_PROFILE=production docker compose run --rm builder

build-nocache:
	@echo "Building Pimeleon image (no cache)..."
	docker compose build --no-cache builder
	docker compose run --rm builder

check-deps:
	@echo "Checking local build dependencies..."
	@./scripts/check-local-deps.sh

# Test targets
test: build
	@echo "Running full test suite..."
	docker-compose build tester
	docker-compose run --rm -e TEST_SUITE=all tester

test-smoke: build
	@echo "Running smoke tests..."
	docker-compose build tester
	docker-compose run --rm -e TEST_SUITE=smoke tester

test-integration: build
	@echo "Running integration tests..."
	docker-compose build tester
	docker-compose run --rm -e TEST_SUITE=integration tester

test-security: build
	@echo "Running security tests..."
	docker-compose build tester
	docker-compose run --rm -e TEST_SUITE=security tester

# Development targets
dev:
	@echo "Starting development environment..."
	docker-compose up -d dev
	@echo "Development environment is ready. Use 'make shell' to enter."

shell:
	@echo "Opening shell in development container..."
	docker-compose exec dev /bin/bash || docker-compose run --rm dev /bin/bash

# Linting targets
lint: lint-yaml lint-shell lint-ansible lint-docker

lint-yaml:
	@echo "Linting YAML files..."
	@docker run --rm -v $(PWD):/workspace cytopia/yamllint -c .yamllint .

lint-shell:
	@echo "Linting shell scripts..."
	@docker run --rm -v $(PWD):/workspace koalaman/shellcheck-alpine \
		find /workspace -name "*.sh" -type f -exec shellcheck {} \;

lint-ansible:
	@echo "Linting Ansible playbooks..."
	@docker run --rm -v $(PWD):/workspace \
		cytopia/ansible-lint ansible/playbooks/*.yml

lint-docker:
	@echo "Linting Dockerfiles..."
	@docker run --rm -i hadolint/hadolint < containers/builder/Dockerfile
	@docker run --rm -i hadolint/hadolint < containers/tester/Dockerfile

# Documentation
docs:
	@echo "Building documentation..."
	@mkdir -p docs
	@docker run --rm -v $(PWD):/workspace -w /workspace \
		sphinxdoc/sphinx-latexpdf \
		sphinx-quickstart -q -p "Pimeleon Build System" -a "Pimeleon Team" -v "1.0" --ext-autodoc --ext-viewcode --makefile docs/

# Cleanup targets
clean:
	@echo "Cleaning build artifacts..."
	rm -rf output/*.img output/*.tar.gz output/pimeleon-*
	rm -rf cache/*
	rm -rf tests/results/*
	docker-compose down -v

clean-all: clean
	@echo "Removing all containers and images..."
	docker-compose down -v --rmi all

# Utility targets
logs:
	docker-compose logs -f

ps:
	docker-compose ps

# CI/CD simulation
ci-local:
	@echo "Running local CI pipeline..."
	$(MAKE) lint
	$(MAKE) build
	$(MAKE) test-smoke
	@echo "Local CI pipeline completed!"

# Version information
version:
	@echo "Pimeleon Build System v1.0.0"
	@echo "Docker version:"
	@docker --version
	@echo "Docker Compose version:"
	@docker-compose --version
