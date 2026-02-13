# SQL CES Load Generator

Synthetic CRUD workload generator for validating the SQL Change Event Streaming POC.

## Features

- **Schema Management**: Uses `yoyo-migrations` for idempotent schema deployment
- **Continuous CRUD**: Generates realistic INSERT/UPDATE/DELETE operations
- **Multi-tenant**: Runs against multiple databases with differentiated patterns
- **Azure Native**: Uses Managed Identity for SQL authentication

## Local Development

```bash
# Install uv (if not already installed)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Create virtual environment and install dependencies
uv sync

# Run (requires SQL_SERVER env var and network access)
SQL_SERVER=your-server.database.windows.net uv run loadgen
```

## Container Build

```bash
# Build the container
docker build -t sql-ces-loadgen .

# Run locally (for testing with SQL auth - not recommended for production)
docker run -e SQL_SERVER=your-server.database.windows.net sql-ces-loadgen
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SQL_SERVER` | (required) | SQL Server FQDN |
| `DATABASES` | `tenant_db_alpha,tenant_db_beta` | Comma-separated list of databases |
| `MIN_DELAY_SECONDS` | `1` | Minimum delay between operations |
| `MAX_DELAY_SECONDS` | `5` | Maximum delay between operations |
| `MIGRATIONS_PATH` | `/app/migrations` | Path to yoyo migrations |

## Migrations

Migrations are managed via `yoyo-migrations` and applied automatically on startup:

- `0001_initial_schema.py` - Customers, Orders, OrderItems tables
- `0002_row_count_view.py` - Reconciliation view
- `0003_schema_change_log.py` - DDL audit trigger

To add a new migration:

```bash
uv run yoyo new ./migrations -m "description"
```

## Operations Distribution

The generator performs weighted random operations:

| Operation | Weight | Description |
|-----------|--------|-------------|
| Insert customer + order | 40% | New customer with order and items |
| Update order status | 30% | Progress order through workflow |
| Insert order for existing | 15% | New order for random customer |
| Update customer | 10% | Modify customer email |
| Delete order item | 5% | Cancel item from pending order |
