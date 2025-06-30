# Multi-stage build for optimized final image
FROM python:3.13-alpine AS builder

# Set build environment variables
ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1

# Install build dependencies
RUN apk add --no-cache --virtual .build-deps \
        gcc \
        musl-dev \
        libffi-dev \
    && apk add --no-cache \
        ca-certificates

# Copy and install Python dependencies
COPY src/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --upgrade pip==24.3.1 && \
    pip install --no-cache-dir --user -r /tmp/requirements.txt && \
    find /root/.local -depth \
        \( \
            \( -type d -a \( -name test -o -name tests -o -name idle_test -o -name __pycache__ \) \) \
            -o \
            \( -type f -a \( -name '*.pyc' -o -name '*.pyo' -o -name '*.pyd' \) \) \
        \) -exec rm -rf '{}' + && \
    apk del .build-deps

# Production stage
FROM python:3.13-alpine

# Set production environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/src \
    PORT=8000 \
    PATH="/app/.local/bin:$PATH" \
    PYTHONUSERBASE=/app/.local

# Install runtime dependencies only
RUN apk add --no-cache \
        curl \
        ca-certificates \
        tini \
    && rm -rf /var/cache/apk/*

# Create non-root user for security
RUN addgroup -g 1000 appuser && \
    adduser -u 1000 -G appuser -s /bin/sh -D appuser

# Set working directory
WORKDIR /app

# Copy Python packages from builder stage
COPY --from=builder --chown=appuser:appuser /root/.local /app/.local

# Copy source code with proper ownership
COPY --chown=appuser:appuser src/ ./src/

# Switch to non-root user
USER appuser

# Expose port
EXPOSE ${PORT}

# Optimized health check with tini
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=2 \
    CMD curl -f http://localhost:${PORT}/ || exit 1

# Use tini as init system for proper signal handling
ENTRYPOINT ["/sbin/tini", "--"]

# Command to run the application
CMD ["python", "src/main.py"]
