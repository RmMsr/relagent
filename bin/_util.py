import shutil
import subprocess
import sys
from os import PathLike


def find_container_framework() -> str:
    framework = next((f for f in ["podman", "docker"] if shutil.which(f)), None)
    if framework is None:
        print("Neither podman nor docker is installed.")
        sys.exit(1)
    print(f"Using framework {framework}")
    return framework


def run_subprocess(
    args: list[str],
    *,
    cwd: PathLike[str] | None = None,
    input: bytes | None = None,
    quiet: bool = False,
    raise_error: bool = False,
) -> bool:
    try:
        kwargs = {}
        if quiet:
            kwargs["stdout"] = subprocess.DEVNULL
            kwargs["stderr"] = subprocess.DEVNULL
        return (
            subprocess.run(
                args=args,
                cwd=cwd,
                input=input,
                check=True,
                **kwargs,  # type: ignore[arg-type]
            ).returncode
            == 0
        )
    except subprocess.CalledProcessError as e:
        command = " ".join(args)
        if not quiet:
            print(f"{args[0]} failed with exit code {e.returncode}.", file=sys.stderr)
            print(f"Command: {command}", file=sys.stderr)
        if raise_error:
            raise
        return False


def ensure_registry_login() -> None:
    if not run_subprocess(
        ["podman", "login", "--get-login", "registry.gitlab.com"], quiet=True
    ):
        print("Logging in to registry.gitlab.com...")
        secret_name = "relagent-registry"
        username = input("Registry username: ")

        secret_exists = run_subprocess(
            ["podman", "secret", "exists", secret_name], quiet=True
        )

        if not secret_exists:
            password = input("Registry secret: ")
            print(f"Storing password as secret '{secret_name}'...")
            run_subprocess(
                ["podman", "secret", "create", secret_name, "-"],
                input=password.encode("utf-8"),
            )
        else:
            print(
                f"Trying to use existing password from secret '{secret_name}'. Try removing it if login fails."
            )

        run_subprocess(
            [
                "podman",
                "login",
                "--username",
                username,
                "--secret",
                secret_name,
                "registry.gitlab.com",
            ]
        )
