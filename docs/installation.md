# Installation

Relagent can be installed in different ways depending on your needs and abilities to self-host.

## Overview

For apps:

- Use the web app that comes with the Relagent engine.
- Build and install mobile and desktop apps from source.

Relagent engine:

- Run the pre-built container youself
  - On Linux using Systemd and Podman (least effort)
  - Using your individual setup
- Use a hosting provider for containerized applications

LLM inference:

- Local running Open AI compatible inference
- Use a 3rd party API

## Starting from source code

To get started you need to build and run all parts yourself.

First: Get a copy of the source code:

```shell
git clone https://gitlab.com/RmMsr/relagent.git
```

## Relagent App

The user facing interface is be built using the [Flutter SDK](https://docs.flutter.dev/install).

Make sure your mobile device is connected and configured for debugging via ADB. Then build and install the Android app:

```shell
cd apps
flutter build apk
flutter install
```

iOS and desktop versions should work, but are currently untested.

Relagent requires a running OpenAI compatible inference server. Like [LM Studio](https://lmstudio.ai/), [Lemonade-Server](https://lemonade-server.ai/), [vLLM](https://github.com/vllm-project/vllm) or [Ollama](https://github.com/ollama/ollama).

## Relagent Engine

The Relagent server requires a Linux operating system to run. The easiest setup is using `podman` and `systemd`. You can also use Docker or run the Python service standalone.

### Automated local setup

If you have a Linux with systemd support, you can use the automated setup to run the engine as a permanent system service. If you don't know systemd, you most likely already have it available.

In addition you need [Podman](https://podman.io/) to securely run the engine as rootless user in a container. Alternatively you can do the same with Docker. But this requires manual setup.

> This guide will be using `podman` in the documentation. Podman is recommended since it has a more secure mode of operation (rootless container with user namespace) by default. You can use almost the same commands with `docker`.

```shell
bin/server_install.py
```

Data is by default stored in `~/.local/share/org.venkado.relagent-engine/`. Please review the `settings.ini` file there.

After installation the API should be running. You can check by browsing to `http://localhost:8000/health`. If everything worked you will get an `ok` message.

For troubleshooting those commands could be helpful:

```shell
systemctl --user status relagent.service
journalctl --user --unit=relagent.service --lines=30 --follow
```

If the `relagent.service` is missing or outdated, a problem with the podman generator is likely. Check:

```shell
journalctl --user --grep=generator --since=-1h
```

#### Auto update

In order to benefit from auto update feature, we enabled the podman-auto-update and run it every 5 minutes. Inspect it using:

```shell
systemctl --user status podman-auto-update.timer
systemctl --user status podman-auto-update.service
```

### Running at a hosting provider

You can use a professional cloud or hosting provider to run the engine. They will run the engine container for you an allow you to access it via HTTPS. The engine can for example run as a serverless on demand service or continuously as a managed container.

The URL for the most recent stable container image is: `registry.gitlab.com/venkado/relagent/relagent-engine:latest`

To avoid surprising updates, use a specific version tag like `:0.1.2` instead of `:latest`.

The configuration for the container can be set via a mounted settings file. or as environmental variables. See [`settings-template.ini`](run/settings-template.ini) for some examples.

### Standalone or development setup

Required software:

- [uv](https://docs.astral.sh/uv/getting-started/installation/) Python package manager

Prepare settings and data directory:

```shell
mkdir -p ~/.local/share/org.venkado.relagent-engine/data
cp run/settings-template.ini ~/.local/share/org.venkado.relagent-engine/settings.ini
uv sync
uv run uvicorn --reload --reload-dir=engine engine.api.run:app
```

For production performance you can run the server from a container:

```shell
bin/server_run.py
```

Or standalone:

```shell
uv run --module engine.run
```

## Monitoring

For traces run an gen_ai compatible open telemetry destination like Phoenix:

```shell
podman run --publish=6006:6006 -i docker.io/arizephoenix/phoenix:latest
```
