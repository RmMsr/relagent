import shutil
import subprocess
import sys


def find_container_framework() -> str:
    framework = next((f for f in ["podman", "docker"] if shutil.which(f)), None)
    if framework is None:
        print("Neither podman nor docker is installed.")
        sys.exit(1)
    print(f"Using framework {framework}")
    return framework

def run_subprocess(args: list[str], *, cwd: str | None = None) -> None:
    try:
        subprocess.run(args=args, cwd=cwd, check=True)
    except subprocess.CalledProcessError as e:
        command = ' '.join(args)
        print(f"{command} failed with exit code {e.returncode}.", file=sys.stderr)
        print(f"Command: {command}", file=sys.stderr)
        sys.exit(1)
