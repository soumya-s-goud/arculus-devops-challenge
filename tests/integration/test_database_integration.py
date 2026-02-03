import sys
from sqlalchemy.exc import SQLAlchemyError
import pytest
from apps.main import app, db, Order

sys.path.insert(0, "../../")


@pytest.fixture
def app_context():
    """
    Fixture to set up the Flask app context and manage a clean database state.
    """
    with app.app_context():
        try:
            print("[SETUP] Initializing database...")
            # Verify database connection
            db.session.execute("SELECT 1")
            print("[SETUP] Connection verified.")

            # Recreate database tables
            print("[SETUP] Recreating database tables...")
            db.drop_all()
            db.create_all()
            print("[SETUP] Tables ready.")

            yield  # Provide the initialized app context to the test

        finally:
            # Cleanup database after tests
            print("[TEARDOWN] Cleaning up database...")
            db.session.remove()
            db.drop_all()
            print("[TEARDOWN] Database cleanup complete.")


def test_database_create_order(app_context):
    """
    Test creating an order in the database and ensure proper validation.
    """
    print("[TEST] Starting test_database_create_order")

    # Ensure no conflicting existing order
    existing_order = Order.query.filter_by(id="integration_test").first()
    if existing_order:
        print("[TEST] Removing existing order with ID 'integration_test'")
        db.session.delete(existing_order)
        db.session.commit()

    # Add a new order
    print("[TEST] Adding and committing a new order")
    new_order = Order(id="integration_test", amount=200.0)
    db.session.add(new_order)

    # Commit and handle potential errors
    try:
        db.session.commit()
    except SQLAlchemyError as error:
        pytest.fail(f"[TEST] Failed to commit order: {str(error)}")

    # Validate the inserted order
    print("[TEST] Validating the newly created order")
    order = Order.query.filter_by(id="integration_test").first()
    assert order is not None, "[TEST] Order not found in the database"
    assert order.id == "integration_test", "[TEST] Order ID mismatch"
    assert order.amount == 200.0, "[TEST] Order amount mismatch"

    print("[TEST] test_database_create_order completed successfully!")
