# Relatable Agentic Minion

An AI powered assistant for daily use with informed privacy decisions.

The primary use case is an agentic chat agent running on a self hosted server with full control which data is used and where it goes.

## Features

- Simple AI conversation
- Speech input and output (on device in English)

**Please note:** This software has the state of a proof of concept. Several aspects are on purpose left out for simplicity:

- App not yet published in appstores
- Only marginally tested setup and update routines
- Multi language support (the default ASR streaming model can be easily replaced)
- Multi user support
- API key management (You can add HTTP basic auth on top of the backend)

## Installation

To get started you need to build and run all parts yourself.

First: Get a copy of the source code:

```
git clone https://gitlab.com/RmMsr/relagent.git
```

### App: Your user interface

The app is be built using the [Flutter SDK](https://docs.flutter.dev/install).

Make sure your mobile device is connected and configured for debugging via ADB. Then build and install the Android app:

```
cd apps
flutter build apk
flutter install
```

iOS and desktop versions should work, but are currently untested.

Relagent requires a running OpenAI compatible inference server. Like [LM Studio](https://lmstudio.ai/), [Lemonade-Server](https://lemonade-server.ai/), [vLLM](https://github.com/vllm-project/vllm) or [Ollama](https://github.com/ollama/ollama).

### Engine: The backend server

The Relagent server requires a Linux operating system to run. The easiest setup is using `podman` and `systemd`. You can also use Docker or run the Python service standalone.

#### Automated setup

If you have a Linux with systemd support, you can use the automated setup to run the engine as a permanent system service. If you don't know systemd, you most likely already have it available.

In addition you need [Podman](https://podman.io/) to securely run the engine as rootless user in a container. Alternatively you can do the same with Docker. But this requires manual setup.

```
bin/server_install.py
```

Data is by default stored in `~/.local/share/relagent/`. Please review the `settings.ini` file there.

After installation the API should be running. You can check by browsing to `http://localhost:8000/status`. If everything worked you will get an `OK` message.

For troubleshooting those commands could be helpful:

```
systemctl --user status relagent.service
journalctl --user --unit=relagent.service --lines=30 --follow
```

If the `relagent.service` is missing or outdated, a problem with the podman generator is likely. Check:

```
journalctl --user --grep=generator --since=-1h
```

#### Auto update

In order to benefit from auto update feature, we enabled the podman-auto-update and run it every 5 minutes. Inspect it using:

```
systemctl --user status podman-auto-update.timer
systemctl --user status podman-auto-update.service
```

### Standalone or development setup

Required software:
- [uv](https://docs.astral.sh/uv/getting-started/installation/) Python package manager

Prepare settings and data directory:

```
mkdir -p ~/.local/share/relagent/data
cp settings.ini.template ~/.local/share/relagent/settings.ini
uv sync
uv run uvicorn --reload --reload-dir=engine engine.run:app
```

For production performance you can run the server from a container:

```
bin/server_run.py
```

Or standalone:

```
uv run --module engine.run
```

## Monitoring

For traces run an gen_ai compatible open telemetry destination like Phoenix:

```
podman run --publish=6006:6006 -i docker.io/arizephoenix/phoenix:latest
```

## License

Free and open source software. Released under [BSD 2-Clause License](license.txt).

Use it as you want. If you distribute or modify it, keep an easy discoverable reference to source and license.
