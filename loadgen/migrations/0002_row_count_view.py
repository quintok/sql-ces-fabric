"""
Add row count view for reconciliation.
"""

from yoyo import step

__depends__ = {"0001_initial_schema"}

steps = [
    step(
        """
        CREATE VIEW dbo.vw_TableRowCounts AS
        SELECT 
            DB_NAME() AS TenantId,
            s.name AS SchemaName,
            t.name AS TableName,
            p.rows AS RowCount,
            GETUTCDATE() AS SnapshotTime
        FROM sys.tables t
        JOIN sys.schemas s ON t.schema_id = s.schema_id
        JOIN sys.partitions p ON t.object_id = p.object_id AND p.index_id IN (0, 1)
        WHERE t.name IN ('Customers', 'Orders', 'OrderItems')
        """,
        "DROP VIEW dbo.vw_TableRowCounts"
    ),
]
