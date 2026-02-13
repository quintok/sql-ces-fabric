# syntax=docker/dockerfile:1
# SQL CES Load Generator - Python with uv

FROM python:3.12-slim AS builder

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Install build dependencies for pyodbc
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    unixodbc-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy project files
COPY pyproject.toml README.md ./
COPY src/ src/

# Create virtual environment and install dependencies
RUN uv venv /app/.venv
RUN uv pip install --python /app/.venv/bin/python .

# ============================================================================
# Runtime stage
# ============================================================================
FROM python:3.12-slim AS runtime

# Install ODBC Driver 18 for SQL Server and runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gnupg2 \
    unixodbc \
    && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/debian/12/prod bookworm main" > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy virtual environment from builder
COPY --from=builder /app/.venv /app/.venv

# Copy migrations
COPY migrations/ /app/migrations/

# Set environment
ENV PATH="/app/.venv/bin:$PATH"
ENV PYTHONUNBUFFERED=1
ENV MIGRATIONS_PATH=/app/migrations

# Default configuration (override via environment)
ENV DATABASES=tenant_db_alpha,tenant_db_beta
ENV MIN_DELAY_SECONDS=1
ENV MAX_DELAY_SECONDS=5

# Run the load generator
CMD ["python", "-m", "loadgen.main"]
