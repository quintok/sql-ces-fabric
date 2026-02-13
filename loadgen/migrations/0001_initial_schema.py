"""
Initial schema - Customers, Orders, OrderItems tables.
"""

from yoyo import step

__depends__ = {}

steps = [
    step(
        # Create Customers table
        """
        CREATE TABLE dbo.Customers (
            CustomerId INT IDENTITY(1,1) PRIMARY KEY,
            FirstName NVARCHAR(100) NOT NULL,
            LastName NVARCHAR(100) NOT NULL,
            Email NVARCHAR(255) NOT NULL,
            CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
            ModifiedAt DATETIME2 DEFAULT GETUTCDATE()
        )
        """,
        # Rollback
        "DROP TABLE dbo.Customers"
    ),
    step(
        # Create Orders table
        """
        CREATE TABLE dbo.Orders (
            OrderId INT IDENTITY(1,1) PRIMARY KEY,
            CustomerId INT NOT NULL,
            OrderDate DATETIME2 DEFAULT GETUTCDATE(),
            TotalAmount DECIMAL(18,2) NOT NULL,
            Status NVARCHAR(50) NOT NULL DEFAULT 'Pending',
            CONSTRAINT FK_Orders_Customers FOREIGN KEY (CustomerId) 
                REFERENCES dbo.Customers(CustomerId)
        )
        """,
        # Rollback
        "DROP TABLE dbo.Orders"
    ),
    step(
        # Create OrderItems table
        """
        CREATE TABLE dbo.OrderItems (
            OrderItemId INT IDENTITY(1,1) PRIMARY KEY,
            OrderId INT NOT NULL,
            ProductName NVARCHAR(200) NOT NULL,
            Quantity INT NOT NULL,
            UnitPrice DECIMAL(18,2) NOT NULL,
            CONSTRAINT FK_OrderItems_Orders FOREIGN KEY (OrderId) 
                REFERENCES dbo.Orders(OrderId)
        )
        """,
        # Rollback
        "DROP TABLE dbo.OrderItems"
    ),
    step(
        # Create index on Orders.CustomerId for FK lookups
        """
        CREATE INDEX IX_Orders_CustomerId ON dbo.Orders(CustomerId)
        """,
        "DROP INDEX IX_Orders_CustomerId ON dbo.Orders"
    ),
    step(
        # Create index on OrderItems.OrderId for FK lookups
        """
        CREATE INDEX IX_OrderItems_OrderId ON dbo.OrderItems(OrderId)
        """,
        "DROP INDEX IX_OrderItems_OrderId ON dbo.OrderItems"
    ),
]
