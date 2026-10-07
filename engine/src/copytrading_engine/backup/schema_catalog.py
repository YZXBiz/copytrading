"""The operational SQLite components that backups carry, and their expected catalogs."""

import re
import sqlite3
from pathlib import Path

from copytrading_engine.control.sqlite import CONTROL_AUDIT_SCHEMA
from copytrading_engine.execution.adapters.sqlite_ledger import EXECUTION_SCHEMA
from copytrading_engine.host.installation import APPLICATION_DATABASE_VERSION, INSTALLATION_SCHEMA
from copytrading_engine.host.self_test.store import SELF_TEST_SCHEMA
from copytrading_engine.parsing.sqlite import PARSER_CORRECTIONS_SCHEMA, PARSER_SCHEMA
from copytrading_engine.shared.sqlite import SchemaComponent, ensure_schema
from copytrading_engine.sources.sqlite import REJECTED_ATTACHMENT_SCHEMA, SOURCE_SCHEMA
from copytrading_engine.trading.adapters.routing import ROUTING_SCHEMA

__all__ = [
    "ACCOUNT_COMPONENTS",
    "APPLICATION_COMPONENTS",
    "APPLICATION_DATABASE_VERSION",
    "create_application_schema",
    "current_operational_schema_catalog",
]

APPLICATION_COMPONENTS: tuple[SchemaComponent, ...] = (
    INSTALLATION_SCHEMA,
    SELF_TEST_SCHEMA,
    PARSER_SCHEMA,
    PARSER_CORRECTIONS_SCHEMA,
    SOURCE_SCHEMA,
    REJECTED_ATTACHMENT_SCHEMA,
    ROUTING_SCHEMA,
    CONTROL_AUDIT_SCHEMA,
)
ACCOUNT_COMPONENTS: tuple[SchemaComponent, ...] = (EXECUTION_SCHEMA,)


def create_application_schema(path: Path) -> None:
    """Give application.db its complete format up front, so an installation is backup-ready
    before trading ever starts. Each store still verifies its own component when it opens."""
    connection = sqlite3.connect(path, timeout=5, isolation_level=None)
    try:
        connection.execute("BEGIN IMMEDIATE")
        for component in APPLICATION_COMPONENTS:
            ensure_schema(connection, component)
        connection.execute("COMMIT")
    except BaseException:
        if connection.in_transaction:
            connection.execute("ROLLBACK")
        raise
    finally:
        connection.close()


_ACCOUNT_DATABASE = re.compile(r"^accounts/[A-Za-z0-9_-]{1,64}/execution\.sqlite3$")


def current_operational_schema_catalog(
    member_path: str,
) -> tuple[tuple[str, str, str, str], ...]:
    """Build a schema catalog from the components used to create operational stores."""
    if member_path == "application.db":
        components = APPLICATION_COMPONENTS
    elif _ACCOUNT_DATABASE.fullmatch(member_path):
        components = ACCOUNT_COMPONENTS
    else:
        raise ValueError("unsupported operational SQLite member")
    connection = sqlite3.connect(":memory:")
    try:
        for component in components:
            ensure_schema(connection, component)
        objects = connection.execute(
            "SELECT type,name,tbl_name,sql FROM sqlite_master "
            "WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name"
        ).fetchall()
        return tuple(
            (kind, name, table_name, statement.strip())
            for kind, name, table_name, statement in objects
            if isinstance(statement, str)
        )
    finally:
        connection.close()
