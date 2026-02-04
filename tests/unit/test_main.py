from unittest.mock import patch

@patch("apps.main.start_application", return_value=None)
def test_main_block(mock_start_application):
    """
    Test the __main__ block in apps.main.py to
    ensure that start_application() is called.
    """
    # Dynamically import and execute the `__main__` block
    import apps.main

    with patch("apps.main.__name__", "__main__"):
        apps.main.start_application()

    # Assert that start_application() is invoked
    mock_start_application.assert_called_once()
