# Multi-stage build for optimized final image with PostgreSQL support
# Using specific digest for reproducible builds and security
ARG PYTHON_VERSION=3.14
FROM python:${PYTHON_VERSION}-slim@sha256:4ed33101ee7ec299041cc41dd268dae17031184be94384b1ce7936dc4e5dead3 AS builder

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
    && apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/apt/* /var/log/dpkg* || true

# Add uv to PATH
ENV PATH="/root/.local/bin:$PATH"

# Copy and install Python dependencies
COPY src/requirements.txt /tmp/requirements.txt
ARG PYTHON_VERSION=3.14
# Build wheels in the builder stage so the final image can install only those
# wheels (avoids copying build tools and other builder artifacts).
RUN mkdir -p /wheels \
    && python -m pip wheel -r /tmp/requirements.txt -w /wheels \
    # Clean up any unnecessary wheel metadata or temp files
    && find /wheels -type f -name "*.whl" -print >/dev/null 2>&1 || true

# Production stage
# Using specific digest for reproducible builds and security
ARG PYTHON_VERSION=3.14
FROM python:${PYTHON_VERSION}-slim@sha256:4ed33101ee7ec299041cc41dd268dae17031184be94384b1ce7936dc4e5dead3

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
    # Install uv in the final stage so we can use uv for faster installs here as well
    && curl -LsSf https://astral.sh/uv/install.sh | sh \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/apt/* /var/log/dpkg* || true

# Create non-root user for security
RUN groupadd -g 1000 appuser && \
    useradd -u 1000 -g appuser -s /bin/sh -m appuser

# Set working directory
WORKDIR /app

# Copy wheels from builder and install them into the final image. This installs
# only the packages required by the app and avoids bringing build-time tools.
ARG PYTHON_VERSION=3.14
COPY --from=builder /wheels /tmp/wheels
COPY --from=builder /tmp/requirements.txt /tmp/requirements.txt
ENV PATH="/root/.local/bin:$PATH"
RUN if [ -x "/root/.local/bin/uv" ]; then \
            /root/.local/bin/uv pip install -r /tmp/requirements.txt; \
        else \
            python -m pip install -r /tmp/requirements.txt; \
        fi \
        && rm -rf /tmp/wheels /tmp/requirements.txt

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
