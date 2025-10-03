# Multi-stage build for optimized final image with PostgreSQL support
# Using specific digest for reproducible builds and security
ARG PYTHON_VERSION=3.13
FROM python:${PYTHON_VERSION}.7-slim-bookworm@sha256:fcf02c9e248b995ae2ca9aac6fa24b489f34b589dbfdc44698ad245d2ad41d1e AS builder

# Set build environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Install system dependencies for building
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gcc \
    libc6-dev \
    libpq-dev \
    ca-certificates \
    # Install uv for faster package management
    && curl -LsSf https://astral.sh/uv/install.sh | sh \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Add uv to PATH
ENV PATH="/root/.local/bin:$PATH"

# Copy and install Python dependencies
COPY src/requirements.txt /tmp/requirements.txt
ARG PYTHON_VERSION=3.13
RUN uv pip install --system -r /tmp/requirements.txt \
    # Remove unnecessary files to reduce image size
    && find /usr/local/lib/python${PYTHON_VERSION}/site-packages -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true \
    && find /usr/local/lib/python${PYTHON_VERSION}/site-packages -type d -name "test" -exec rm -rf {} + 2>/dev/null || true \
    && find /usr/local/lib/python${PYTHON_VERSION}/site-packages -name "*.pyc" -delete \
    && find /usr/local/lib/python${PYTHON_VERSION}/site-packages -name "*.pyo" -delete \
    && find /usr/local/lib/python${PYTHON_VERSION}/site-packages -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

# Production stage
# Using specific digest for reproducible builds and security
ARG PYTHON_VERSION=3.13
FROM python:${PYTHON_VERSION}.7-slim-bookworm@sha256:fcf02c9e248b995ae2ca9aac6fa24b489f34b589dbfdc44698ad245d2ad41d1e

# Metadata labels for OCI compliance
LABEL org.opencontainers.image.title="Python LAMP Web App" \
    org.opencontainers.image.description="FastAPI application with PostgreSQL support" \
    org.opencontainers.image.source="https://github.com/jaredthivener/python-lamp-web-app" \
    org.opencontainers.image.version="1.0.0"

# Set production environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/src \
    PORT=8000

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    tini \
    ca-certificates \
    openssl \
    libssl3 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN groupadd -g 1000 appuser && \
    useradd -u 1000 -g appuser -s /bin/sh -m appuser

# Set working directory
WORKDIR /app

# Copy Python packages from builder stage (only site-packages, not all of /usr/local/bin)
ARG PYTHON_VERSION=3.13
COPY --from=builder /usr/local/lib/python${PYTHON_VERSION}/site-packages /usr/local/lib/python${PYTHON_VERSION}/site-packages

# Copy source code with proper ownership
COPY --chown=appuser:appuser src/ ./src/

# Switch to non-root user
USER appuser

# Expose port
EXPOSE 8000

# Health check for FastAPI application - uses existing /health endpoint
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health', timeout=3).read()" || exit 1

# Use tini as init system for proper signal handling
ENTRYPOINT ["/usr/bin/tini", "--"]

# Command to run the application
CMD ["python", "-u", "src/main.py"]
