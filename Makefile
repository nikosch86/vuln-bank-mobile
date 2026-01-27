# VulnBank Mobile Build System
#
# Build Android APKs for all security levels using Docker (same environment as CI)
#
# Usage:
#   make build-android    # Build all security levels (release)
#   make build-debug      # Build all security levels (debug)
#   make clean            # Clean build artifacts
#
# Security Levels:
#   L0 (none)            - No pinning, baseline for testing
#   L1 (library)         - JS-based pinning with react-native-ssl-pinning
#   L2 (proxy-bypass)    - L1 + proxy detection
#   L3 (custom)          - Native SSL pinning modules
#   L4 (frida-resistant) - L3 + anti-tampering, root detection
#
# Requirements:
#   - Docker installed and running
#   - Internet connection (for npm dependencies)

.PHONY: help build-android build-debug clean clean-all shell lint test info docker-build

# Docker images
# Custom image with pre-installed SDK (faster builds)
DOCKER_IMAGE_CUSTOM := vulnbank-android
# Base image (fallback)
DOCKER_IMAGE_BASE := reactnativecommunity/react-native-android
# Use custom image if it exists, otherwise use base
DOCKER_IMAGE := $(shell docker images -q $(DOCKER_IMAGE_CUSTOM) 2>/dev/null | grep -q . && echo $(DOCKER_IMAGE_CUSTOM) || echo $(DOCKER_IMAGE_BASE))

# Project directory (mounted into container)
PROJECT_DIR := $(shell pwd)

# All security levels to build
SECURITY_LEVELS := none library proxy-bypass custom frida-resistant

# Output directory for built APKs
OUTPUT_DIR := $(PROJECT_DIR)/build-output

# Gradle cache directory (persisted between builds)
GRADLE_CACHE_DIR := $(PROJECT_DIR)/.gradle-cache

# CPU/parallel build settings
# Use all available cores, or set explicitly: make build-android JOBS=8
JOBS ?= $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

# Gradle optimization flags
GRADLE_OPTS := --parallel \
	--daemon \
	--build-cache \
	-Dorg.gradle.workers.max=$(JOBS) \
	-Dorg.gradle.parallel=true \
	-Dorg.gradle.caching=true \
	-Dorg.gradle.configureondemand=true \
	-Dkotlin.incremental=true

# Default target
help:
	@echo "VulnBank Mobile Build System"
	@echo ""
	@echo "Usage: make <target> [JOBS=N]"
	@echo ""
	@echo "Setup (run once):"
	@echo "  docker-build     Build custom Docker image with pre-installed SDK (faster builds)"
	@echo ""
	@echo "Build Targets:"
	@echo "  build-android    Build release APKs for ALL security levels"
	@echo "  build-debug      Build debug APKs for ALL security levels"
	@echo "  install          Install npm dependencies in container"
	@echo ""
	@echo "Other Targets:"
	@echo "  clean            Clean build artifacts"
	@echo "  clean-all        Clean everything including node_modules"
	@echo "  shell            Open shell in build container"
	@echo "  lint             Run linter"
	@echo "  test             Run tests"
	@echo "  info             Show configuration"
	@echo ""
	@echo "Options:"
	@echo "  JOBS=N           Number of parallel jobs (default: auto-detect CPUs)"
	@echo "                   Example: make build-android JOBS=8"
	@echo ""
	@echo "Security Levels Built:"
	@echo "  L0 (none)            - No pinning (baseline)"
	@echo "  L1 (library)         - JS-based SSL pinning"
	@echo "  L2 (proxy-bypass)    - SSL pinning + proxy detection"
	@echo "  L3 (custom)          - Native SSL pinning"
	@echo "  L4 (frida-resistant) - Full security suite"
	@echo ""
	@echo "Output: ./build-output/app-{level}-{release|debug}.apk"

# Create output directory
$(OUTPUT_DIR):
	mkdir -p $(OUTPUT_DIR)

# Create gradle cache directory
$(GRADLE_CACHE_DIR):
	mkdir -p $(GRADLE_CACHE_DIR)

# Build custom Docker image with pre-installed Android SDK
docker-build:
	@echo "Building custom Docker image with pre-installed SDK..."
	@echo "This may take a few minutes on first run."
	docker build -t $(DOCKER_IMAGE_CUSTOM) .
	@echo ""
	@echo "Done! Custom image '$(DOCKER_IMAGE_CUSTOM)' is ready."
	@echo "Future builds will use this image automatically."

# Install dependencies (run once before building)
install:
	@echo "Installing dependencies..."
	docker run --rm \
		-v $(PROJECT_DIR):/app \
		-w /app \
		$(DOCKER_IMAGE) \
		npm ci

# Build release APKs for all security levels (optimized: single container, one npm ci)
build-android: $(OUTPUT_DIR) $(GRADLE_CACHE_DIR)
	@echo "========================================"
	@echo "Building ALL security levels (release)"
	@echo "Using $(JOBS) parallel jobs"
	@echo "========================================"
	@echo ""
	docker run --rm \
		-v $(PROJECT_DIR):/app \
		-v $(GRADLE_CACHE_DIR):/root/.gradle \
		-w /app \
		-e GRADLE_OPTS="-Dorg.gradle.workers.max=$(JOBS) -Xmx4g" \
		$(DOCKER_IMAGE) \
		sh -c '\
			echo "Installing dependencies (once)..." && \
			npm ci --prefer-offline 2>/dev/null || npm ci && \
			echo "" && \
			for level in none library proxy-bypass custom frida-resistant; do \
				echo "----------------------------------------"; \
				echo "Building: $$level (release)"; \
				echo "----------------------------------------"; \
				cat /app/.env /app/.env.$$level > /app/.env.build && \
				cd /app/android && \
				SECURITY_LEVEL=$$level ./gradlew assembleRelease \
					$(GRADLE_OPTS) \
					--console=plain && \
				mkdir -p /app/build-output && \
				cp /app/android/app/build/outputs/apk/release/app-release.apk \
					/app/build-output/app-$$level-release.apk && \
				echo "Built: app-$$level-release.apk" && \
				echo ""; \
			done && \
			echo "========================================" && \
			echo "Build complete!" && \
			echo "========================================" && \
			ls -lh /app/build-output/*.apk'

# Build debug APKs for all security levels (optimized: single container, one npm ci)
build-debug: $(OUTPUT_DIR) $(GRADLE_CACHE_DIR)
	@echo "========================================"
	@echo "Building ALL security levels (debug)"
	@echo "Using $(JOBS) parallel jobs"
	@echo "========================================"
	@echo ""
	docker run --rm \
		-v $(PROJECT_DIR):/app \
		-v $(GRADLE_CACHE_DIR):/root/.gradle \
		-w /app \
		-e GRADLE_OPTS="-Dorg.gradle.workers.max=$(JOBS) -Xmx4g" \
		$(DOCKER_IMAGE) \
		sh -c '\
			echo "Installing dependencies (once)..." && \
			npm ci --prefer-offline 2>/dev/null || npm ci && \
			echo "" && \
			for level in none library proxy-bypass custom frida-resistant; do \
				echo "----------------------------------------"; \
				echo "Building: $$level (debug)"; \
				echo "----------------------------------------"; \
				cat /app/.env /app/.env.$$level > /app/.env.build && \
				cd /app/android && \
				SECURITY_LEVEL=$$level ./gradlew assembleDebug \
					$(GRADLE_OPTS) \
					--console=plain && \
				mkdir -p /app/build-output && \
				cp /app/android/app/build/outputs/apk/debug/app-debug.apk \
					/app/build-output/app-$$level-debug.apk && \
				echo "Built: app-$$level-debug.apk" && \
				echo ""; \
			done && \
			echo "========================================" && \
			echo "Build complete!" && \
			echo "========================================" && \
			ls -lh /app/build-output/*.apk'

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts and caches..."
	docker run --rm \
		-v $(PROJECT_DIR):/app \
		-w /app \
		$(DOCKER_IMAGE) \
		sh -c "rm -rf /app/build-output && \
			rm -rf /app/android/app/build && \
			rm -rf /app/android/.gradle && \
			rm -rf /app/node_modules/.cache && \
			rm -rf /app/.env.build && \
			rm -rf /app/.metro-health-check*"
	@echo "Clean complete"

# Clean everything including node_modules and gradle cache
clean-all: clean
	@echo "Removing node_modules and gradle cache..."
	rm -rf $(PROJECT_DIR)/node_modules
	rm -rf $(GRADLE_CACHE_DIR)
	@echo "Clean all complete"

# Open shell in build container for debugging
shell:
	@echo "Opening shell in build container..."
	docker run --rm -it \
		-v $(PROJECT_DIR):/app \
		-v $(GRADLE_CACHE_DIR):/root/.gradle \
		-w /app \
		$(DOCKER_IMAGE) \
		/bin/bash

# Run linter
lint:
	docker run --rm \
		-v $(PROJECT_DIR):/app \
		-w /app \
		$(DOCKER_IMAGE) \
		sh -c "npm ci && npm run lint"

# Run tests
test:
	docker run --rm \
		-v $(PROJECT_DIR):/app \
		-w /app \
		$(DOCKER_IMAGE) \
		sh -c "npm ci && npm test"

# Show current configuration
info:
	@echo "Configuration:"
	@echo "  Docker image:    $(DOCKER_IMAGE)"
	@if [ "$(DOCKER_IMAGE)" = "$(DOCKER_IMAGE_CUSTOM)" ]; then \
		echo "                   (custom image with pre-installed SDK)"; \
	else \
		echo "                   (base image - run 'make docker-build' for faster builds)"; \
	fi
	@echo "  Project dir:     $(PROJECT_DIR)"
	@echo "  Output dir:      $(OUTPUT_DIR)"
	@echo "  Gradle cache:    $(GRADLE_CACHE_DIR)"
	@echo "  Security levels: $(SECURITY_LEVELS)"
	@echo "  Parallel jobs:   $(JOBS)"
	@echo ""
	@echo "Gradle optimizations:"
	@echo "  $(GRADLE_OPTS)" | tr ' ' '\n' | sed 's/^/  /'
	@echo ""
	@echo "Environment files:"
	@for level in $(SECURITY_LEVELS); do \
		if [ -f "$(PROJECT_DIR)/.env.$$level" ]; then \
			echo "  .env.$$level - OK"; \
		else \
			echo "  .env.$$level - MISSING"; \
		fi; \
	done
	@echo ""
	@echo "Docker status:"
	@docker info > /dev/null 2>&1 && echo "  Docker is running" || echo "  Docker is NOT running"
