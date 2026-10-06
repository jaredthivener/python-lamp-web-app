# ------------------------------------------------------------------------
# 🐍 Multi-stage build for FastAPI + PostgreSQL with UV package manager
# ------------------------------------------------------------------------
# The version and digest are written out in both FROM lines rather than passed through an ARG,
# which Dependabot cannot read: with an ARG here it never proposes a newer Python.
FROM python:3.14.8-slim-trixie@sha256:f85c5697265c178cc6887276c55fe16cf3d14ca35c3df6a5eab3b360534a55d2 AS builder

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

# Copy dependency list (pyproject.toml is the single source of truth)
COPY pyproject.toml /tmp/pyproject.toml

# Install Python dependencies into isolated /deps directory
RUN mkdir -p /deps \
    && uv pip install --no-cache-dir --target /deps -r /tmp/pyproject.toml

# ------------------------------------------------------------------------
# 🏗️ Production Stage
# ------------------------------------------------------------------------
FROM python:3.14.8-slim-trixie@sha256:f85c5697265c178cc6887276c55fe16cf3d14ca35c3df6a5eab3b360534a55d2

# OCI Metadata
LABEL org.opencontainers.image.title="Python LAMP Web App" \
    org.opencontainers.image.description="FastAPI application with PostgreSQL support" \
    org.opencontainers.image.source="https://github.com/jaredthivener/python-lamp-web-app" \
    org.opencontainers.image.version="2.0.0" \
    org.opencontainers.image.vendor="Jared Thivener" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.sbom="true"

# Environment variables for runtime
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/src \
    PORT=8000

# Install runtime deps (no compilers, no apt cache left behind). No libpq here: psycopg2-binary
# loads the copy inside its own wheel, so the system one would only be something to patch.
RUN apt-get update && apt-get install -y --no-install-recommends \
    tini ca-certificates \
    # Cleanup: aggressively remove APT metadata and logs
    && rm -rf /var/lib/apt/lists/* /var/cache/* /usr/share/doc/* /usr/share/man/* /var/log/* /tmp/* \
    # Nothing is installed at run time, and pip carries its own copies of libraries that fall behind
    && pip uninstall --yes --root-user-action=ignore pip

# Create non-root user. The fixed ID is what lets Kubernetes verify runAsNonRoot: it
# cannot tell from a name alone that the user is not root.
RUN groupadd -r -g 10001 appuser && useradd -r -u 10001 -g appuser -s /bin/sh -m appuser

# Working directory
WORKDIR /app/src

# Copy dependencies from builder
COPY --from=builder /deps /usr/local/lib/python3.14/site-packages

# Copy source code
COPY --chown=10001:10001 src/ .

# Switch to non-root user
USER 10001:10001

# Expose FastAPI port
EXPOSE 8000

# Healthcheck endpoint
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/livez', timeout=3).read()" || exit 1

# Entrypoint and command
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["python", "-u", "main.py"]

# ------------------------------------------------------------------------
# 🧬 SBOM (Software Bill of Materials) generation (optional build target)
# ------------------------------------------------------------------------
# You can generate an SBOM via:
#    docker sbom python-lamp-web-app:test
# ------------------------------------------------------------------------
