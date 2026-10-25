# ------------------------------------------------------------------------
# 🐍 Multi-stage build for FastAPI + PostgreSQL with UV package manager
# ------------------------------------------------------------------------
# The version and digest are written out in each FROM line rather than passed through an ARG,
# which Dependabot cannot read: with an ARG here it never proposes a newer Python.
FROM python:3.15.0-slim-trixie@sha256:f5b92f2a669a4c347044f29367f31983280b648250ca94dea66f98c53bc87e58 AS builder

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
# 📦 Runtime files stage: the interpreter, the dependencies and the libraries they load
# ------------------------------------------------------------------------
# Still the official Python image, so the interpreter is the one Python ships. Nothing here is
# shipped except what the production stage copies out of /usr/local and /rootfs.
FROM python:3.15.0-slim-trixie@sha256:f5b92f2a669a4c347044f29367f31983280b648250ca94dea66f98c53bc87e58 AS runtime

# The system libraries the interpreter's extension modules load that the production base does not
# have (it has libc, libssl, zlib, zstd, libgcc and libstdc++), and tini. No libpq: psycopg2-binary
# loads the copy inside its own wheel. A wheel or Python version that needs another library fails the
# CI step "Check the image's libraries load": add its package here.
ARG RUNTIME_PACKAGES="libbz2-1.0 libffi8 liblzma5 libmpdec4 libsqlite3-0 tini"

# "install" brings packages that are already installed up to the newest version, so these are
# current when the image is built. Nothing is installed at run time, and pip carries its own
# copies of libraries that fall behind.
RUN apt-get update && apt-get install -y --no-install-recommends $RUNTIME_PACKAGES \
    && rm -rf /var/lib/apt/lists/* \
    && pip uninstall --yes --root-user-action=ignore pip

COPY --from=builder /deps /usr/local/lib/python3.15/site-packages

# Extension modules the app does not use, whose libraries carry findings that have no fix: curses
# and readline (ncurses), gdbm and dbm, and uuid (libuuid, from util-linux). uuid1() still works
# without its C module, which azure-core calls for request IDs: it takes a random node ID instead
# of the MAC address. tkinter goes too: it needs a Tk that this image never had.
RUN cd /usr/local/lib/python3.15/lib-dynload && rm _curses*.so readline*.so _gdbm*.so _dbm*.so _uuid*.so _tkinter*.so

# The libraries as files, plus a dpkg status entry for each package, which is how the production base
# lists its own packages: without it a scanner would not know these libraries are there.
RUN mkdir -p /rootfs/var/lib/dpkg/status.d \
    && dpkg -L $RUNTIME_PACKAGES | grep -E '\.so|/bin/tini$' | tar -cf - -T - | tar -xf - -C /rootfs \
    && for package in $RUNTIME_PACKAGES; do dpkg-query --status "$package" > "/rootfs/var/lib/dpkg/status.d/$package"; done

# ------------------------------------------------------------------------
# 🏗️ Production Stage
# ------------------------------------------------------------------------
# Distroless: no shell, no package manager, no setuid programs, none of Debian's util-linux, ncurses,
# systemd, perl or login. "cc" is the variant with libgcc and libstdc++, which the Rust wheels
# (cryptography, pydantic-core) load. Like the Python image above, its version and digest are
# written out so Dependabot proposes newer ones.
FROM gcr.io/distroless/cc-debian13:nonroot@sha256:3ee00291cf386ec52a552e6a858d555debd74776eb4bfa53fa3df2cd6677515e

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

COPY --from=runtime /usr/local /usr/local
COPY --from=runtime /rootfs/ /

# Working directory
WORKDIR /app/src

# Copy source code
COPY --chown=10001:10001 src/ .

# Run as a non-root user. The fixed ID is what lets Kubernetes verify runAsNonRoot: it cannot tell
# from a name alone that the user is not root. The ID needs no /etc/passwd entry.
USER 10001:10001

# Expose FastAPI port
EXPOSE 8000

# Healthcheck endpoint. Exec form because there is no shell; an exception exits non-zero.
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/livez', timeout=3).read()"]

# Entrypoint and command
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["python", "-u", "main.py"]

# ------------------------------------------------------------------------
# 🧬 SBOM (Software Bill of Materials) generation (optional build target)
# ------------------------------------------------------------------------
# You can generate an SBOM via:
#    docker sbom python-lamp-web-app:test
# ------------------------------------------------------------------------
