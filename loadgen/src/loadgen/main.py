"""Main entry point for the load generator."""

import os
import sys
import time

import structlog
from yoyo import get_backend, read_migrations

from loadgen.generator import LoadGenerator

log = structlog.get_logger()


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
    structlog.configure(
        processors=[
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.add_log_level,
            structlog.dev.ConsoleRenderer()
            if sys.stdout.isatty()
            else structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.BoundLogger,
        context_class=dict,
        logger_factory=structlog.PrintLoggerFactory(),
    )

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
