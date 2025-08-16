# Multi-stage build for optimized final image with PostgreSQL support
FROM python:3.13.7-slim AS builder

# Set build environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

# Install system dependencies for building
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    build-essential \
    libpq-dev \
    ca-certificates \
    # Install uv for faster package management
    && curl -LsSf https://astral.sh/uv/install.sh | sh \
    # Clean up
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Add uv to PATH
ENV PATH="/root/.local/bin:$PATH"

# Copy and install Python dependencies
COPY src/requirements.txt /tmp/requirements.txt
RUN uv pip install --system -r /tmp/requirements.txt

# Production stage
FROM python:3.13.7-slim

# Set production environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/src \
    PORT=8000

# Install runtime dependencies for PostgreSQL
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    libpq5 \
    tini \
    ca-certificates \
    # Clean up
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN groupadd -g 1000 appuser && \
    useradd -u 1000 -g appuser -s /bin/bash -m appuser

# Set working directory
WORKDIR /app

# Copy Python packages from builder stage
COPY --from=builder /usr/local/lib/python3.13/site-packages /usr/local/lib/python3.13/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

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
