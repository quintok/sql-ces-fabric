# syntax=docker/dockerfile:1
# SQL CES Load Generator - Python with uv

# Pin to Bookworm to match Microsoft ODBC driver repository
FROM python:3.12-slim-bookworm AS builder

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
# Pin to Bookworm to match Microsoft ODBC driver repository
# Note: ODBC Driver 18 requires x86_64 - use --platform linux/amd64 at build time
FROM python:3.12-slim-bookworm AS runtime

# Install ODBC Driver 18 for SQL Server and runtime dependencies
# Split into separate commands for better error visibility during build
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gnupg2 \
    unixodbc \
    && rm -rf /var/lib/apt/lists/*

# Add Microsoft repository and install ODBC driver
RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/debian/12/prod bookworm main" > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Verify ODBC driver is properly installed and registered
RUN odbcinst -q -d -n "ODBC Driver 18 for SQL Server" || (echo "ODBC Driver installation failed!" && cat /etc/odbcinst.ini && exit 1)

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
