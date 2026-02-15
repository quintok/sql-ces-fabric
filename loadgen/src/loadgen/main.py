"""Main entry point for the load generator."""

import logging
import os
import sys
import time

import structlog
from yoyo import get_backend, read_migrations

from loadgen.generator import LoadGenerator

log = structlog.get_logger()


def configure_azure_monitor() -> None:
    """Configure Azure Monitor OpenTelemetry if connection string is available."""
    connection_string = os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING")
    if not connection_string:
        log.info("azure_monitor_disabled", reason="No connection string")
        return

    try:
        from azure.monitor.opentelemetry import (
            configure_azure_monitor as setup_azure_monitor,
        )

        setup_azure_monitor(
            connection_string=connection_string,
            enable_live_metrics=True,
        )
        log.info("azure_monitor_configured")
    except ImportError:
        log.warning("azure_monitor_not_available", reason="Package not installed")
    except Exception as e:
        log.warning("azure_monitor_failed", error=str(e))


def get_connection_string(database: str) -> str:
    """Build ODBC connection string for Azure SQL with Entra ID auth."""
    server = os.environ["SQL_SERVER"]

    # Use Managed Identity authentication for Azure SQL
    return (
        f"Driver={{ODBC Driver 18 for SQL Server}};"
        f"Server={server};"
        f"Database={database};"
        "Authentication=ActiveDirectoryMsi;"
        "Encrypt=yes;"
        "TrustServerCertificate=no;"
    )


def get_yoyo_connection_string(database: str) -> str:
    """Build yoyo-migrations connection string (uses pyodbc under the hood)."""
    server = os.environ["SQL_SERVER"]

    # yoyo uses a different URL format
    # For Azure SQL with MSI, we need to use the odbc:// scheme
    return (
        f"mssql+pyodbc://@{server}/{database}"
        "?driver=ODBC+Driver+18+for+SQL+Server"
        "&Authentication=ActiveDirectoryMsi"
        "&Encrypt=yes"
        "&TrustServerCertificate=no"
    )


def run_migrations(databases: list[str], migrations_path: str) -> None:
    """Run yoyo migrations against all databases."""
    for db in databases:
        log.info("running_migrations", database=db)
        try:
            backend = get_backend(get_yoyo_connection_string(db))
            migrations = read_migrations(migrations_path)

            with backend.lock():
                backend.apply_migrations(backend.to_apply(migrations))

            log.info("migrations_complete", database=db)
        except Exception as e:
            log.error("migration_failed", database=db, error=str(e))
            raise


def main() -> int:
    """Main entry point."""
    # Configure standard logging first (OpenTelemetry hooks into this)
    logging.basicConfig(
        level=logging.INFO,
        format="%(message)s",
        stream=sys.stdout,
    )

    # Configure Azure Monitor for Application Insights telemetry
    configure_azure_monitor()

    # Configure structlog to use Python's standard logging as backend
    # This allows Azure Monitor to capture all structured logs
    structlog.configure(
        processors=[
            structlog.stdlib.filter_by_level,
            structlog.stdlib.add_logger_name,
            structlog.stdlib.add_log_level,
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            structlog.processors.UnicodeDecoder(),
            structlog.stdlib.ProcessorFormatter.wrap_for_formatter,
        ],
        wrapper_class=structlog.stdlib.BoundLogger,
        context_class=dict,
        logger_factory=structlog.stdlib.LoggerFactory(),
        cache_logger_on_first_use=True,
    )

    # Add JSON formatting for structured logging
    formatter = structlog.stdlib.ProcessorFormatter(
        processor=structlog.dev.ConsoleRenderer()
        if sys.stdout.isatty()
        else structlog.processors.JSONRenderer(),
    )
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(formatter)

    root_logger = logging.getLogger()
    root_logger.handlers = [handler]
    root_logger.setLevel(logging.INFO)

    # Configuration from environment
    databases = os.environ.get("DATABASES", "tenant_db_alpha,tenant_db_beta").split(",")
    migrations_path = os.environ.get("MIGRATIONS_PATH", "/app/migrations")
    min_delay = float(os.environ.get("MIN_DELAY_SECONDS", "1"))
    max_delay = float(os.environ.get("MAX_DELAY_SECONDS", "5"))

    log.info(
        "starting_load_generator",
        databases=databases,
        min_delay=min_delay,
        max_delay=max_delay,
    )

    # Run migrations first
    run_migrations(databases, migrations_path)

    # Create generators for each database
    generators = [
        LoadGenerator(
            connection_string=get_connection_string(db),
            database_name=db,
            min_delay=min_delay,
            max_delay=max_delay,
        )
        for db in databases
    ]

    # Run load generation loop
    log.info("starting_crud_loop")
    try:
        while True:
            for gen in generators:
                gen.execute_random_operation()
                time.sleep(gen.get_random_delay())
    except KeyboardInterrupt:
        log.info("shutdown_requested")
        return 0
    except Exception as e:
        log.error("fatal_error", error=str(e))
        return 1


if __name__ == "__main__":
    sys.exit(main())
