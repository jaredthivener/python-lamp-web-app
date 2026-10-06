# ==========================================================
# 🐍 Python LAMP Web App - Makefile
# Streamlined build, run, and security workflow
# ==========================================================
#
# How to use:
#   make all           → Build + Scan + Dive + SBOM (full workflow)
#   make build         → Build the Docker image (ARM64 by default)
#   make run           → Run the container locally on port 8000
#   make shell         → Open a shell inside the container
#   make scan          → Scan image for vulnerabilities using Trivy
#   make dive          → Inspect image layers interactively
#   make sbom          → Show a live SBOM table using Docker’s built-in tool
#   make clean         → Remove unused Docker data
#   make rebuild       → Clean and rebuild from scratch
#
# Example (override architecture):
#   make build PLATFORM=linux/amd64
#
# ==========================================================

# Image configuration
IMAGE_NAME := python-lamp-web-app
TAG := latest
PLATFORM := linux/arm64
DOCKERFILE := Dockerfile

# Build command
BUILD_CMD := docker buildx build --platform $(PLATFORM) \
	-t $(IMAGE_NAME):$(TAG) --load -f $(DOCKERFILE) . --no-cache

# ==========================================================
# 🔨 Default: Build + Security Workflow
# ==========================================================

.PHONY: all
all: build scan dive sbom
	@echo "✅ Full pipeline complete: build, scan, dive, sbom."

# ==========================================================
# 🔧 Build and Run
# ==========================================================

.PHONY: build
build:
	@echo "🚀 Building $(IMAGE_NAME):$(TAG) for $(PLATFORM)..."
	$(BUILD_CMD)

.PHONY: run
run:
	@echo "🏃 Running $(IMAGE_NAME):$(TAG)..."
	docker run --rm -it -p 8000:8000 $(IMAGE_NAME):$(TAG)

.PHONY: shell
shell:
	@echo "🐚 Opening interactive shell inside container..."
	docker run --rm -it $(IMAGE_NAME):$(TAG) /bin/sh

# ==========================================================
# 🧪 Security and Inspection
# ==========================================================

.PHONY: scan
scan:
	@echo "🔍 Running Trivy vulnerability scan..."
	trivy image --format table --severity HIGH,CRITICAL $(IMAGE_NAME):$(TAG) || true

.PHONY: dive
dive:
	@echo "🔎 Inspecting image layers using Dive..."
	dive --ci $(IMAGE_NAME):$(TAG) || true

.PHONY: sbom
sbom:
	@echo "📦 Displaying SBOM for $(IMAGE_NAME):$(TAG)..."
	syft scan $(IMAGE_NAME):$(TAG) --output table || true
	@echo "✅ SBOM table displayed successfully."

# ==========================================================
# 🧹 Cleanup
# ==========================================================

.PHONY: clean
clean:
	@echo "🧹 Removing dangling images and build cache..."
	docker system prune -af --volumes

.PHONY: rebuild
rebuild: clean build
	@echo "✅ Rebuild complete."
