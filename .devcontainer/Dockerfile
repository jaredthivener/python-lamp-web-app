FROM mcr.microsoft.com/devcontainers/python:1-3.13-bullseye

# Install additional system dependencies
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    postgresql-client \
    curl \
    wget \
    git \
    build-essential \
    libpq-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*


# Install uv for faster Python package management and ensure it's available for all users
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && ln -sf /root/.local/bin/uv /usr/local/bin/uv
ENV PATH="/root/.local/bin:$PATH"

# Copy project files and install dependencies using uv
COPY pyproject.toml /tmp/pyproject.toml
COPY src/requirements.txt /tmp/requirements.txt
WORKDIR /tmp

# Install project dependencies and dev dependencies using uv
RUN uv pip install --system -r /tmp/requirements.txt && \
    uv pip install --system \
    pytest \
    pytest-asyncio \
    pytest-cov \
    black \
    flake8 \
    mypy \
    pre-commit \
    httpx \
    pytest-mock

# Clean up
RUN rm -rf /tmp/pyproject.toml /tmp/requirements.txt

# Create workspace directory
WORKDIR /workspaces/python-lamp-web-app

# Set Python path
ENV PYTHONPATH=/workspaces/python-lamp-web-app/src

# Expose the port the app runs on
EXPOSE 8000

# Default command
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
