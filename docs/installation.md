# Installation

Relagent can be installed in different ways depending on your needs and abilities to self-host.

## Overview

You have several choices to get and install the building blocks. The Engine is the only required component. In most cases you want to also install the Relagent apps and a dedicated inference server.

Your most common options are listed below.

### Relagent engine

- Run the pre-built container yourself
  - On Linux using Systemd and Podman (the least effort)
  - Any other container engine
- Use a hosting provider for containerized applications

### Relagent apps

This is the user interface for interaction with the agent.

- Use the web app that comes with the Relagent engine
- Install a mobile app from an app store. Currently, only [Google play store](https://play.google.com/store/apps/details?id=org.venkado.relagent) is available
- Build and install mobile and desktop apps from source (windows, linux, macOS)

### LLM inference

- Use the bundled relagent engine, for example the `latest-bundled` container tag.
- Local running OpenAI chat completion compatible inference server.
- Use a third-party API.

**Please Note**: Using the bundled inference server (based on llama.cpp) gives only limited performance and should not be considered for a permanent installation.

## Starting from source code

To get started, you need to build and run some parts yourself.

First: Get a copy of the source code:

```shell
git clone https://gitlab.com/RmMsr/relagent.git
```

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

You can use a professional cloud or hosting provider to run the engine. They will run the engine container for you and allow you to access it via HTTPS. The engine can for example run as a serverless on demand service or continuously as a managed container.

The URL for the most recent stable container image is: `registry.gitlab.com/rmmsr/relagent:latest`

To avoid surprising updates, use a specific version tag like `:0.1.2` instead of `:latest`.

The configuration for the container can be set via a mounted settings file or as environment variables. See [`settings-template.ini`](run/settings-template.ini) for some examples.

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

## Relagent App

The user-facing interface is built using the [Flutter SDK](https://docs.flutter.dev/install).

Make sure your mobile device is connected and configured for debugging via ADB. Then build and install the Android app:

```shell
cd apps
flutter build apk
flutter install
```

iOS and desktop versions should work but are currently untested.

## LLM inference

Relagent requires a running OpenAI compatible inference service, like [LM Studio](https://lmstudio.ai/), [Lemonade-Server](https://lemonade-server.ai/), [Ollama](https://github.com/ollama/ollama) or [llama.cpp server](https://llama-cpp.com/).

**LM Studio** is a good choice to get going with local LLM inference. It comes with a graphical user interface and runs on Linux, macOS and Windows. The application helps you choose fitting models and runs them on CPU or GPU (nVidia=CUDA, AMD=ROCm and Intel=Vulkan). This example assumes you have the lm studio server running with default settings.

There are many ways to get good inference performance. As a base, look for a computer with a good amount of RAM. Up to 24 GB if you can.

Then focus on a graphics card that has a compatible chip with tensor cores or matrix cores and again as much onboard RAM as possible. 16 to 24 GB is very good. Popular choices are:

- Nvidia GeForce RTX 3xxx, 4xxx and 5xxx series
- AMD Radeon RX 6xxx or 7xxx series

### Picking a generative AI model

There exist many models capable of performing the relevant agentic tasks. What you need is a text-generating Large Language model with so-called tool (or function) calling capabilities. In typical local execution scenarios, the model must be in the [GGUF format](https://en.wikipedia.org/wiki/GGUF).

A good source is the model catalog inside LM Studio, or once you have an idea what you need the [Hugging Face Hub](https://huggingface.co/models) to find a suitable variant. Both tools help you to assess which models probably fit your hardware.

Assuming you have a working LM Studio server, look for the Google open-weights model "Gemma 4 E4B" in "My Models" and download it (~ 6.5 GiB, id=`google/gemma-4-e4b`). If you need a smaller model, look for the 2-billion-parameter model "Gemma 4 E2B" (~ 4.5 GiB, id=`google/gemma-4-e2b`).

Some alternatives that should work well are: `gpt-oss`, `nemotron-3`, and `olmo3`.

## Monitoring

For traces run a gen_ai compatible OpenTelemetry destination like Phoenix:

```shell
podman run --publish=6006:6006 -i docker.io/arizephoenix/phoenix:latest
```
