# Relatable Agentic Minion

An AI powered assistant for daily use with informed privacy decisions.

The primary use case is an agentic chat agent running on a self hosted server with full control which data is used and where it goes.

## Features

- Simple AI conversation
- Speech input (on device in English)

**Please note:** This software has the state of a proof of concept. Several aspects are on purpose left out for simplicity:

- Multi language support (the default ASR streaming model can be easily replaced)
- Multi user support
- Authentication (we assume your server is accessible via a local IP address)

## Installation

### App

The app can be built using flutter.

For Android:

```
cd apps
flutter build apk
flutter install
```

The Relagent app requires a running OpenAI compatible server. Like [LM Studio](https://lmstudio.ai/), [Lemonade-Server](https://lemonade-server.ai/), [vLLM](https://github.com/vllm-project/vllm) or [Ollama](https://github.com/ollama/ollama).

### Server (outdated, will be replaced)

The relagent chat server can be installed as user level systemd service.

```
bin/server-install.py
```

After installation you can access the chat via `http://localhost:3000`.

#### Auto update

In order to benefit from auto update feature, we enabled the podman-auto-update and run it every 5 minutes. Inspect it using:

```
systemctl --user status podman-auto-update.timer
systemctl --user status podman-auto-update.service
```

### Development

Create a `.env` file from `.env.template` and set relevant variables.

Then build and run the container:

```
bin/server-build.py
podman run --rm --publish 3000:7860 relagent
```

## License

Free and open source software. Released under [BSD 2-Clause License](license.txt).

Use it as you want. If you distribute or modify it, keep an easy discoverable reference to source and license.
