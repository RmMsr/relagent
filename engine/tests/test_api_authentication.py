from unittest.mock import patch

from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient

from engine.api.v1 import require_api_key


class TestApiAuthentication:
    def test_request_with_secret_key(self):
        with patch("engine.api.helpers.SECRET_ACCESS_KEY", "test_api_key"):
            app = FastAPI()

            @app.get("/", dependencies=[Depends(require_api_key)])
            def get_with_secret_key():
                return {"message": "Hello World"}

            client = TestClient(app)
            response = client.get("/")
            assert response.status_code == 401

            response = client.get("/", headers={"X-API-Key": "test_api_key"})
            assert response.status_code == 200

    def test_without_secret_key(self):
        with patch("engine.api.helpers.SECRET_ACCESS_KEY", ""):
            app = FastAPI()

            @app.get("/", dependencies=[Depends(require_api_key)])
            def get_without_secret_key():
                return {"message": "Hello World"}

            client = TestClient(app)
            response = client.get("/")
            assert response.status_code == 200

            response = client.get("/", headers={"X-API-Key": "test_api_key"})
            assert response.status_code == 200
