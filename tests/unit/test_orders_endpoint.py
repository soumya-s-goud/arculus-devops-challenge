from apps.main import app, db, Order
import pytest


@pytest.fixture
def client():
    """
    Flask test client with app and database setup.
    """
    with app.test_client() as client:
        with app.app_context():
            db.drop_all()
            db.create_all()
        yield client


def test_create_order(client):
    payload = {"id": "test_order", "amount": 150.00}
    response = client.post("/orders", json=payload)
    assert response.status_code == 201
    assert response.json == {"id": "test_order", "amount": 150.00}


def test_create_order_invalid_input(client):
    """
    Test creating an order with missing fields in the payload.
    """
    response = client.post("/orders", json={"amount": 150.00})
    assert response.status_code == 400
    assert response.json == {
        "error": "Invalid input. 'id' and 'amount' are required fields."
    }


def test_get_orders_empty(client):
    """
    Test retrieving orders when the database is empty.
    """
    response = client.get("/orders")
    assert response.status_code == 200
    assert response.json == []


def test_get_orders_with_data(client):
    """
    Test retrieving orders when the database contains orders.
    """
    with app.app_context():
        # Insert an order into the database
        new_order = Order(id="order1", amount=123.45)
        db.session.add(new_order)
        db.session.commit()

    response = client.get("/orders")
    assert response.status_code == 200
    assert response.json == [{"id": "order1", "amount": 123.45}]
