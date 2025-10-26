# ------------------------------------------------------------------------
# 🐍 Multi-stage build for FastAPI + PostgreSQL with UV package manager
# ------------------------------------------------------------------------
ARG PYTHON_VERSION=3.14
FROM python:${PYTHON_VERSION}-slim-bookworm@sha256:4ed33101ee7ec299041cc41dd268dae17031184be94384b1ce7936dc4e5dead3 AS builder

# Environment setup for clean, fast, reproducible builds
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PATH="/root/.local/bin:$PATH"

# Install build dependencies and uv (Rust-based pip replacement)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl gcc libc6-dev libpq-dev ca-certificates \
    && curl -LsSf https://astral.sh/uv/install.sh -o install_uv.sh \
    && sh install_uv.sh \
    # Remove build deps to slim down builder image
    && apt-get purge -y gcc libc6-dev curl \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* /var/log/* /var/cache/* /usr/share/doc/* /usr/share/man/* /tmp/*

# Copy dependency list
COPY src/requirements.txt /tmp/requirements.txt

# Install Python dependencies into isolated /deps directory
RUN mkdir -p /deps \
    && uv pip install --no-cache-dir --target /deps -r /tmp/requirements.txt

# ------------------------------------------------------------------------
# 🏗️ Production Stage
# ------------------------------------------------------------------------
FROM python:${PYTHON_VERSION}-slim-bookworm@sha256:4ed33101ee7ec299041cc41dd268dae17031184be94384b1ce7936dc4e5dead3

# OCI Metadata
LABEL org.opencontainers.image.title="Python LAMP Web App" \
    org.opencontainers.image.description="FastAPI application with PostgreSQL support" \
    org.opencontainers.image.source="https://github.com/jaredthivener/python-lamp-web-app" \
    org.opencontainers.image.version="1.1.0" \
    org.opencontainers.image.vendor="Jared Thivener" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.sbom="true"

# Environment variables for runtime
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/src \
    PATH="/root/.local/bin:$PATH" \
    PORT=8000

# Install runtime deps (no compilers, no apt cache left behind)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl libpq5 tini ca-certificates libssl3 \
    && curl -LsSf https://astral.sh/uv/install.sh -o install_uv.sh \
    && sh install_uv.sh \
    # Cleanup: aggressively remove APT metadata and logs
    && apt-get purge -y curl \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* /var/cache/* /usr/share/doc/* /usr/share/man/* /var/log/* /tmp/*

# Create non-root user
RUN groupadd -r appuser && useradd -r -g appuser -s /bin/sh -m appuser

# Working directory
WORKDIR /app/src

# Copy dependencies from builder
COPY --from=builder /deps /usr/local/lib/python3.14/site-packages

# Copy source code
COPY --chown=appuser:appuser src/ .

# Switch to non-root user
USER appuser

# Expose FastAPI port
EXPOSE 8000

# Healthcheck endpoint
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health', timeout=3).read()" || exit 1

# Entrypoint and command
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["python", "-u", "main.py"]

# ------------------------------------------------------------------------
# 🧬 SBOM (Software Bill of Materials) generation (optional build target)
# ------------------------------------------------------------------------
# You can generate an SBOM via:
#    docker sbom python-lamp-web-app:test
# ------------------------------------------------------------------------
