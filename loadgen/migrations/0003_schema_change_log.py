"""
Add schema change logging for DDL tracking.
"""

from yoyo import step

__depends__ = {"0002_row_count_view"}

steps = [
    step(
        # Schema change tracking table
        """
        CREATE TABLE dbo.SchemaChangeLog (
            ChangeId INT IDENTITY(1,1) PRIMARY KEY,
            EventTime DATETIME2 DEFAULT GETUTCDATE(),
            EventType NVARCHAR(100),
            ObjectName NVARCHAR(256),
            SqlCommand NVARCHAR(MAX)
        )
        """,
        "DROP TABLE dbo.SchemaChangeLog"
    ),
    step(
        # DDL trigger to capture schema changes
        """
        CREATE TRIGGER trg_DDL_SchemaChanges
        ON DATABASE
        FOR ALTER_TABLE, CREATE_TABLE, DROP_TABLE
        AS
        BEGIN
            INSERT INTO dbo.SchemaChangeLog (EventType, ObjectName, SqlCommand)
            SELECT 
                EVENTDATA().value('(/EVENT_INSTANCE/EventType)[1]', 'NVARCHAR(100)'),
                EVENTDATA().value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(256)'),
                EVENTDATA().value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'NVARCHAR(MAX)');
        END
        """,
        "DROP TRIGGER trg_DDL_SchemaChanges ON DATABASE"
    ),
]
