import sys
from apps.main import app
import pytest  # Add pytest import explicitly

# Dynamically adjust the module search path
sys.path.insert(0, "../../")


@pytest.fixture
def client():
    """
    Pytest fixture to create a test client for the Flask app.
    """
    return app.test_client()


def test_health_endpoint(client):
    """
    Test the health check endpoint (/health).
    """
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json == {"status": "ok"}


def test_health_endpoint_invalid_method(client):
    """
    Test invalid HTTP methods on the /health endpoint.
    """
    response = client.post("/health")
    assert response.status_code == 405
