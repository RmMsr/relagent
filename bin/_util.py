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

def run_subprocess(args: list[str], *, cwd: str | None = None, input: str | None = None, quiet: bool = False) -> bool:
    try:
        kwargs = {}
        if quiet:
            kwargs['stdout'] = subprocess.DEVNULL
            kwargs['stderr'] = subprocess.DEVNULL
        return subprocess.run(args=args, cwd=cwd, input=input, check=True, **kwargs).returncode == 0
    except subprocess.CalledProcessError as e:
        command = ' '.join(args)
        print(f"{command} failed with exit code {e.returncode}.", file=sys.stderr)
        print(f"Command: {command}", file=sys.stderr)
        return False
