#!/usr/bin/env python

import os
import shutil
import sys


def main() -> None:
    frameworks = ["podman", "docker"]
    framework = next((f for f in frameworks if shutil.which(f)), None)
    if framework is None:
        print("Neither podman nor docker is installed.")
        sys.exit(1)
    print(f"Using framework {framework}")
    os.system(f"{framework} build --tag=relagent -f Containerfile .")

if __name__ == "__main__":
    main()
