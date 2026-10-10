# ------------------------------------------------------------------------
# 🐍 Multi-stage build for FastAPI + PostgreSQL with UV package manager, on Alpine
# ------------------------------------------------------------------------
# The version and digest are written out in both FROM lines rather than passed through an ARG,
# which Dependabot cannot read: with an ARG here it never proposes a newer Python.
#
# Alpine, not Debian: measured with Trivy 0.75 and Grype 0.120.1 on the finished image, the
# Debian slim base carried 166 findings (almost all with no fix to apply) against 1 on Alpine
# (zlib, which has a fix, and which the build patches with Copacetic: see .github/actions/harden-image).
# It is also about 130 MB smaller. Alpine uses musl: every compiled dependency has a musllinux wheel
# except pyyaml, which pip builds as plain Python (it only matters for uvicorn's YAML log config).
FROM python:3.15.0rc3-alpine3.24@sha256:f288a00331ddad8ddf86aa9d83331f188d9a5b1999dea3762adf2af1968b0c04 AS builder

# Environment setup for clean, fast, reproducible builds
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# uv (Rust-based pip replacement) from Alpine's signed package repository, rather than a script
# fetched from the internet. No compiler: every dependency installs from a wheel except pyyaml.
RUN apk add --no-cache uv

# Copy dependency list (pyproject.toml is the single source of truth)
COPY pyproject.toml /tmp/pyproject.toml

# Install Python dependencies into isolated /deps directory
RUN mkdir -p /deps \
    && uv pip install --no-cache-dir --target /deps -r /tmp/pyproject.toml

# ------------------------------------------------------------------------
# 🏗️ Production Stage
# ------------------------------------------------------------------------
FROM python:3.15.0rc3-alpine3.24@sha256:f288a00331ddad8ddf86aa9d83331f188d9a5b1999dea3762adf2af1968b0c04

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

# Install runtime deps (no compilers, no package cache left behind). No libpq here: psycopg2-binary
# loads the copy inside its own wheel, so the system one would only be something to patch.
RUN apk add --no-cache tini \
    # Nothing is installed at run time, and pip carries its own copies of libraries that fall behind
    && pip uninstall --yes --root-user-action=ignore pip

# Create non-root user. The fixed ID is what lets Kubernetes verify runAsNonRoot: it
# cannot tell from a name alone that the user is not root.
RUN addgroup -S -g 10001 appuser && adduser -S -u 10001 -G appuser appuser

# Working directory
WORKDIR /app/src

# Copy dependencies from builder
COPY --from=builder /deps /usr/local/lib/python3.15/site-packages

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
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["python", "-u", "main.py"]

# ------------------------------------------------------------------------
# 🧬 SBOM (Software Bill of Materials) generation (optional build target)
# ------------------------------------------------------------------------
# You can generate an SBOM via:
#    docker sbom python-lamp-web-app:test
# ------------------------------------------------------------------------
