"""Main entry point for the load generator."""

import logging
import os
import subprocess
import sys
import time
from pathlib import Path

import structlog
from yoyo import get_backend, read_migrations

from loadgen.generator import LoadGenerator

log = structlog.get_logger()


# >>> ODBC_DIAGNOSTICS - Remove this section after issue is resolved >>>
def diagnose_odbc_setup() -> None:
    """
    Log ODBC driver diagnostic information at startup.
    This helps confirm the driver is properly installed in the container.
    TEMPORARY: Remove after ODBC driver issue is resolved.
    """
    print("=" * 60, flush=True)
    print("ODBC DRIVER DIAGNOSTICS", flush=True)
    print("=" * 60, flush=True)

    # Check 1: List installed ODBC drivers via odbcinst
    try:
        result = subprocess.run(
            ["odbcinst", "-q", "-d"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        print(f"[odbcinst -q -d] Installed drivers:\n{result.stdout}", flush=True)
        if result.stderr:
            print(f"[odbcinst stderr]: {result.stderr}", flush=True)
    except Exception as e:
        print(f"[odbcinst] Failed to query drivers: {e}", flush=True)

    # Check 2: Verify ODBC Driver 18 specifically
    try:
        result = subprocess.run(
            ["odbcinst", "-q", "-d", "-n", "ODBC Driver 18 for SQL Server"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode == 0:
            print("[ODBC Driver 18] Driver is registered ✓", flush=True)
            print(f"  Details: {result.stdout.strip()}", flush=True)
        else:
            print(
                f"[ODBC Driver 18] Driver NOT registered! stderr: {result.stderr}",
                flush=True,
            )
    except Exception as e:
        print(f"[ODBC Driver 18] Check failed: {e}", flush=True)

    # Check 3: Show odbcinst.ini contents
    odbcinst_path = Path("/etc/odbcinst.ini")
    if odbcinst_path.exists():
        print(f"\n[{odbcinst_path}] Contents:", flush=True)
        print(odbcinst_path.read_text(), flush=True)
    else:
        print(f"[{odbcinst_path}] File does not exist!", flush=True)

    # Check 4: Verify driver library exists
    driver_paths = [
        "/opt/microsoft/msodbcsql18/lib64/libmsodbcsql-18.5.so.1.1",
        "/opt/microsoft/msodbcsql18/lib64/libmsodbcsql-18.4.so.1.1",
        "/opt/microsoft/msodbcsql18/lib64/libmsodbcsql-18.3.so.3.1",
    ]
    print("\n[Driver library check]:", flush=True)
    for path in driver_paths:
        if Path(path).exists():
            print(f"  Found: {path} ✓", flush=True)
            break
    else:
        # List what actually exists
        driver_dir = Path("/opt/microsoft/msodbcsql18/lib64")
        if driver_dir.exists():
            files = list(driver_dir.glob("*"))
            print(f"  Driver dir contents: {[f.name for f in files]}", flush=True)
        else:
            print("  /opt/microsoft/msodbcsql18/lib64 does not exist!", flush=True)

    # Check 5: pyodbc drivers list
    try:
        import pyodbc

        drivers = pyodbc.drivers()
        print(f"\n[pyodbc.drivers()] Available: {drivers}", flush=True)
        if "ODBC Driver 18 for SQL Server" in drivers:
            print("  ODBC Driver 18 available to pyodbc ✓", flush=True)
        else:
            print("  WARNING: ODBC Driver 18 NOT in pyodbc.drivers()!", flush=True)
    except Exception as e:
        print(f"[pyodbc.drivers()] Failed: {e}", flush=True)

    print("=" * 60, flush=True)
    print("END ODBC DIAGNOSTICS", flush=True)
    print("=" * 60 + "\n", flush=True)


# <<< ODBC_DIAGNOSTICS <<<


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
    from urllib.parse import quote_plus

    server = os.environ["SQL_SERVER"]

    # Build ODBC connection string
    odbc_conn = (
        f"Driver={{ODBC Driver 18 for SQL Server}};"
        f"Server={server};"
        f"Database={database};"
        "Authentication=ActiveDirectoryMsi;"
        "Encrypt=yes;"
        "TrustServerCertificate=no;"
    )

    # yoyo uses odbc:// scheme with URL-encoded connection string
    return f"odbc:///?odbc_connect={quote_plus(odbc_conn)}"


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
    # >>> ODBC_DIAGNOSTICS - Remove these 2 lines after issue is resolved >>>
    diagnose_odbc_setup()
    # <<< ODBC_DIAGNOSTICS <<<

    # Configure Azure Monitor - it hooks into the logging system
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

    # Add JSON formatting for structured logging to console
    formatter = structlog.stdlib.ProcessorFormatter(
        processor=structlog.dev.ConsoleRenderer()
        if sys.stdout.isatty()
        else structlog.processors.JSONRenderer(),
    )
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(formatter)

    root_logger = logging.getLogger()
    root_logger.addHandler(console_handler)
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
