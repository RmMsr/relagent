#!/usr/bin/env -S uv run --script

import json
import sys
from pathlib import Path


def main():
    # Make engine module available and load app
    project_path = Path(__file__).parent.parent
    sys.path.append(project_path.as_posix())
    from engine.api.run import app

    with open("openapi-schema.json", mode="w") as fh:
        json.dump(app.openapi(), fh, indent=2)

    print("OpenAPI schema generated as openapi-schema.json")


if __name__ == "__main__":
    main()
