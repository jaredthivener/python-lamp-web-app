# Multi-stage build for optimized final image with PostgreSQL support
# Using specific digest for reproducible builds and security
FROM python:3.13.7-slim-bookworm@sha256:fcf02c9e248b995ae2ca9aac6fa24b489f34b589dbfdc44698ad245d2ad41d1e AS builder

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
RUN uv pip install --system -r /tmp/requirements.txt \
    # Remove unnecessary files to reduce image size
    && find /usr/local/lib/python3.13/site-packages -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true \
    && find /usr/local/lib/python3.13/site-packages -type d -name "test" -exec rm -rf {} + 2>/dev/null || true \
    && find /usr/local/lib/python3.13/site-packages -name "*.pyc" -delete \
    && find /usr/local/lib/python3.13/site-packages -name "*.pyo" -delete \
    && find /usr/local/lib/python3.13/site-packages -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

# Production stage
# Using specific digest for reproducible builds and security
FROM python:3.13.7-slim-bookworm@sha256:fcf02c9e248b995ae2ca9aac6fa24b489f34b589dbfdc44698ad245d2ad41d1e

# Set production environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/src \
    PORT=8000

# NOTE: apt-get upgrade is generally NOT recommended in Dockerfiles
# Better practice: Rebuild image when base image updates are released
# Uncomment only if you need critical security patches immediately:
# RUN apt-get update && apt-get upgrade -y --no-install-recommends && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install runtime dependencies for PostgreSQL
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    libpq5 \
    tini \
    ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN groupadd -g 1000 appuser && \
    useradd -u 1000 -g appuser -s /bin/sh -m appuser

# Set working directory
WORKDIR /app

# Copy Python packages from builder stage (only site-packages, not all of /usr/local/bin)
COPY --from=builder /usr/local/lib/python3.13/site-packages /usr/local/lib/python3.13/site-packages

# Copy source code with proper ownership
COPY --chown=appuser:appuser src/ ./src/

# Switch to non-root user
USER appuser

# Expose port
EXPOSE ${PORT}

# Health check for FastAPI application
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=2 \
    CMD curl -f http://localhost:${PORT}/health || exit 1

# Use tini as init system for proper signal handling
ENTRYPOINT ["/usr/bin/tini", "--"]

# Command to run the application
CMD ["python", "src/main.py"]
