from pathlib import Path

import pytest

from engine.adapters.test_adapters import MemoryPersistence
from engine.adapters.yaml_persistence import YamlPersistenceAdapter
from engine.domain.ports.persistence import Persistence


@pytest.fixture(params=["memory", "yaml"])
def persistence(request, tmp_path: Path) -> Persistence:
    if request.param == "memory":
        return MemoryPersistence()
    return YamlPersistenceAdapter(data_dir=tmp_path)
