"""Load generator - performs random CRUD operations against Azure SQL."""

import random

import pyodbc
import structlog
from faker import Faker

log = structlog.get_logger()
fake = Faker()


class LoadGenerator:
    """Generates synthetic CRUD operations for a single database."""

    def __init__(
        self,
        connection_string: str,
        database_name: str,
        min_delay: float = 1.0,
        max_delay: float = 5.0,
    ):
        self.connection_string = connection_string
        self.database_name = database_name
        self.min_delay = min_delay
        self.max_delay = max_delay
        self._connection: pyodbc.Connection | None = None

    @property
    def connection(self) -> pyodbc.Connection:
        """Lazy connection with auto-reconnect."""
        if self._connection is None:
            log.info("connecting_to_database", database=self.database_name)
            self._connection = pyodbc.connect(self.connection_string, autocommit=True)
        return self._connection

    def reconnect(self) -> None:
        """Force reconnection on next operation."""
        if self._connection:
            try:
                self._connection.close()
            except Exception:
                pass
        self._connection = None

    def get_random_delay(self) -> float:
        """Return a random delay between min and max."""
        return random.uniform(self.min_delay, self.max_delay)

    def execute_random_operation(self) -> None:
        """Execute a random CRUD operation with weighted distribution."""
        # Weighted operations: more inserts/updates than deletes
        operations = [
            (self.insert_customer_with_order, 40),  # 40%
            (self.update_order_status, 30),  # 30%
            (self.insert_order_for_existing, 15),  # 15%
            (self.update_customer, 10),  # 10%
            (self.delete_order_item, 5),  # 5%
        ]

        total_weight = sum(w for _, w in operations)
        choice = random.randint(1, total_weight)

        cumulative = 0
        for operation, weight in operations:
            cumulative += weight
            if choice <= cumulative:
                try:
                    operation()
                except pyodbc.Error as e:
                    log.warning(
                        "operation_failed",
                        database=self.database_name,
                        operation=operation.__name__,
                        error=str(e),
                    )
                    self.reconnect()
                break

    def insert_customer_with_order(self) -> None:
        """Insert a new customer with an order and items."""
        cursor = self.connection.cursor()

        # Insert customer
        first_name = fake.first_name()
        last_name = fake.last_name()
        email = fake.email()

        cursor.execute(
            """
            INSERT INTO dbo.Customers (FirstName, LastName, Email)
            OUTPUT INSERTED.CustomerId
            VALUES (?, ?, ?)
            """,
            (first_name, last_name, email),
        )
        customer_id = cursor.fetchone()[0]

        # Insert order
        total_amount = round(random.uniform(10.0, 500.0), 2)
        status = random.choice(["Pending", "Processing", "Shipped"])

        cursor.execute(
            """
            INSERT INTO dbo.Orders (CustomerId, TotalAmount, Status)
            OUTPUT INSERTED.OrderId
            VALUES (?, ?, ?)
            """,
            (customer_id, total_amount, status),
        )
        order_id = cursor.fetchone()[0]

        # Insert 1-3 order items
        num_items = random.randint(1, 3)
        for _ in range(num_items):
            product = fake.word().capitalize() + " " + fake.word().capitalize()
            quantity = random.randint(1, 5)
            unit_price = round(random.uniform(5.0, 100.0), 2)

            cursor.execute(
                """
                INSERT INTO dbo.OrderItems (OrderId, ProductName, Quantity, UnitPrice)
                VALUES (?, ?, ?, ?)
                """,
                (order_id, product, quantity, unit_price),
            )

        log.info(
            "inserted_customer_with_order",
            database=self.database_name,
            customer_id=customer_id,
            order_id=order_id,
            items=num_items,
        )

    def insert_order_for_existing(self) -> None:
        """Insert a new order for an existing customer."""
        cursor = self.connection.cursor()

        # Get a random existing customer
        cursor.execute("SELECT TOP 1 CustomerId FROM dbo.Customers ORDER BY NEWID()")
        row = cursor.fetchone()
        if not row:
            # No customers yet, create one instead
            return self.insert_customer_with_order()

        customer_id = row[0]

        # Insert order
        total_amount = round(random.uniform(10.0, 500.0), 2)
        status = "Pending"

        cursor.execute(
            """
            INSERT INTO dbo.Orders (CustomerId, TotalAmount, Status)
            OUTPUT INSERTED.OrderId
            VALUES (?, ?, ?)
            """,
            (customer_id, total_amount, status),
        )
        order_id = cursor.fetchone()[0]

        # Insert 1-2 order items
        num_items = random.randint(1, 2)
        for _ in range(num_items):
            product = fake.word().capitalize() + " " + fake.word().capitalize()
            quantity = random.randint(1, 3)
            unit_price = round(random.uniform(5.0, 50.0), 2)

            cursor.execute(
                """
                INSERT INTO dbo.OrderItems (OrderId, ProductName, Quantity, UnitPrice)
                VALUES (?, ?, ?, ?)
                """,
                (order_id, product, quantity, unit_price),
            )

        log.info(
            "inserted_order_for_existing",
            database=self.database_name,
            customer_id=customer_id,
            order_id=order_id,
        )

    def update_order_status(self) -> None:
        """Update status of a random order."""
        cursor = self.connection.cursor()

        # Get a random order that isn't completed
        cursor.execute(
            """
            SELECT TOP 1 OrderId, Status 
            FROM dbo.Orders 
            WHERE Status != 'Completed'
            ORDER BY NEWID()
            """
        )
        row = cursor.fetchone()
        if not row:
            return

        order_id, current_status = row

        # Progress to next status
        status_progression = {
            "Pending": "Processing",
            "Processing": "Shipped",
            "Shipped": "Completed",
        }
        new_status = status_progression.get(current_status, "Completed")

        cursor.execute(
            "UPDATE dbo.Orders SET Status = ? WHERE OrderId = ?",
            (new_status, order_id),
        )

        log.info(
            "updated_order_status",
            database=self.database_name,
            order_id=order_id,
            old_status=current_status,
            new_status=new_status,
        )

    def update_customer(self) -> None:
        """Update a random customer's email."""
        cursor = self.connection.cursor()

        cursor.execute("SELECT TOP 1 CustomerId FROM dbo.Customers ORDER BY NEWID()")
        row = cursor.fetchone()
        if not row:
            return

        customer_id = row[0]
        new_email = fake.email()

        cursor.execute(
            """
            UPDATE dbo.Customers 
            SET Email = ?, ModifiedAt = GETUTCDATE() 
            WHERE CustomerId = ?
            """,
            (new_email, customer_id),
        )

        log.info(
            "updated_customer",
            database=self.database_name,
            customer_id=customer_id,
        )

    def delete_order_item(self) -> None:
        """Delete a random order item (simulate cancellation)."""
        cursor = self.connection.cursor()

        # Only delete items from orders that aren't shipped/completed
        cursor.execute(
            """
            SELECT TOP 1 oi.OrderItemId, oi.OrderId
            FROM dbo.OrderItems oi
            JOIN dbo.Orders o ON oi.OrderId = o.OrderId
            WHERE o.Status IN ('Pending', 'Processing')
            ORDER BY NEWID()
            """
        )
        row = cursor.fetchone()
        if not row:
            return

        item_id, order_id = row

        cursor.execute("DELETE FROM dbo.OrderItems WHERE OrderItemId = ?", (item_id,))

        log.info(
            "deleted_order_item",
            database=self.database_name,
            order_item_id=item_id,
            order_id=order_id,
        )
