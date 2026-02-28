# Relagent

<div align="center">

![Relagent logo](docs/media/relagent-logo-01.png)

*A trustworthy AI powered assistant for daily use that keeps you in control over your data.*

**\#PrivacyFirst - \#SelfHosting - \#DataSovereignty - \#DigitalIndependence**

</div>

---

Artificial Intelligence can be very helpful and inspiring to use. But too often it appears as a black box that consumes and produces data without the needed transparency. This project aims to fix that and give back control to users.

The goal of the Relagent project is an accessible solution for agentic AI services with full control over your data. Setting up your own installation should be within reach without considerable technical knowledge or financial investment.

## Current features

- 🗨️ Chat interface
- 📱 Mobile apps, 🖥️ Desktop apps and 🌐 Web interface fully synchronized
- 💽 Local data storage
- 🧰 Agentic tools (e.g. web search)
- 🎤 Speech input (Automatic Speech Recognition) and output (Text To Speech) on the device (mobile and desktop)
- 📑 Multiple parallel sessions

## Quick start

The easiest way to get your personal instance of Relagent (the relatable agentic minion) is to use the containerized setup. More installation options are explained in the [Installation documentation](docs/installation.md).

What you need:

1. **Container runtime**: [Podman](https://podman.io/getting-started/installation) or [Docker](https://docs.docker.com/get-docker/) to run the containerized application.
2. **LLM service**: Access to an OpenAI compatible inference service (API URL and optional API Key). For example:
   - Running locally. For example using [LM Studio](https://lmstudio.ai/), [Ollama](https://ollama.com/download) or [Lemonade-Server](https://lemonade-server.ai/).
   - Using a 3rd party provider who will run the LLM for you. Any provider that supports the OpenAI v1 API should work.
3. **LLM Model**: Please choose a text generating large language model (LLM) available at your inference service. The model needs to support so called tool or function calling. For example `gpt-oss` or `olmo3` should give you a solid start.
4. **Secret Access Key**: A secret only you know to protect access to your service.

> **LM Studio** is a good choice to get going with local LLM inference. It comes with a graphical user interface and runs on Linux, macOS and Windows. The application helps you choose fitting models and runs them on CPU or GPU (nVidia=CUDA, AMD=ROCm and Intel=Vulkan). This example assumes you have the lm studio server running with default settings.
>
> As a starting point locate the OpenAI open-weights model "GPT-OSS 20b" in "My Models" and download it (~ 12 GiB, id=`openai/gpt-oss-20b`). If you need a smaller model, search for "lmstudio-community/Olmo-3-7B-Instruct-GGUF". Pick the "Q4_K_M" version (~5 GiB, id=`olmo-3-7b-instruct`).

First we set configuration via environment variables. Please refer to the [settings.ini template](run/settings-template.ini) for more options and details.

Run those commands in a project directory with a terminal:

```shell
# The URL of the Inference provider (leave out the /chat/completions part)
export PROVIDER_API_BASE=http://host.containers.internal:1234/v1

# The API key for the Inference provider (not needed for local inference)
export PROVIDER_API_KEY=

# The identifier of the default model to use
export PROVIDER_DEFAULT_MODEL=openai/gpt-oss-20b

# The secret access key should be random and long enough so that it cannot be
# guessed. One way to generate it is to use python:
export SERVER_SECRET_ACCESS_KEY=$(
  python -c 'import secrets; print(secrets.token_urlsafe(24))'
)
echo Secret access key: $SERVER_SECRET_ACCESS_KEY

# Create the data directory inside a suitable folder
mkdir -p ./data
```

Now you can start the container using podman:

```shell
# Securely save the secret for use inside the container
podman secret create --env=true relagent-secret-access-key SERVER_SECRET_ACCESS_KEY

# Start the container. Stop it again by pressing [Ctrl] + [C]
podman run \
  --name relagent-engine \
  --rm \
  --env=PROVIDER_API_BASE \
  --env=PROVIDER_API_KEY \
  --env=PROVIDER_DEFAULT_MODEL \
  --secret=relagent-secret-access-key,type=env,target=SERVER_SECRET_ACCESS_KEY \
  --volume=./data:/app/.local/share/org.venkado.relagent-engine/data:rw \
  --publish=8000:8000 \
  --userns=keep-id:uid=1000,gid=1000 \
  registry.gitlab.com/rmmsr/relagent:latest
```

Alternatively using Docker:

```shell
docker run \
  --name relagent-engine \
  --rm \
  --env=PROVIDER_API_BASE \
  --env=PROVIDER_API_KEY \
  --env=PROVIDER_DEFAULT_MODEL \
  --env=SERVER_SECRET_ACCESS_KEY \
  --volume=./data:/app/.local/share/org.venkado.relagent-engine/data:rw \
  --publish=8000:8000 \
  --user=1000:1000 \
  --add-host=host.containers.internal:host-gateway \
  registry.gitlab.com/rmmsr/relagent:latest
```

Now you can access the Relagent web app at [http://localhost:8000/](http://localhost:8000/) in your browser. In order to authorize the connection, you need to set the *secret access key* as Engine API key in the Settings.

## Roadmap

> **Please note:** This software is in a relative early stage and changes are frequent.

Those are some very relevant topics that we would love to spend time on:

- **Explicit cross session memory**: Creating and accessing topic specific long term memory.
- **External triggers**: Allowing external events like calendar entries or scheduled reminders to initiate agent actions.
- **Security gates**: Map execution steps (like thinking, data access or external tool calling) to risks and apply rules and permissions.
- **Evolving context seed**: Allows the agent to step into interactions with distilled knowledge from previous sessions.

## Design decisions and limitations

Several aspects are on purpose out of scope at the moment:

- The mobile and desktop **apps are not yet published in appstores**. Follow the instructions to build them yourself.
- Only **English has full language support**. Other languages have experimental support for voice integration. The interface is not yet localized.
- **Dependency on OpenAI compatible endpoint**. Performing LLM inference directly is not needed for the current featureset. You can choose from many self-hosting options to run your own inference server.
- **Just one user per installation**. No multi user support. You can run multiple instances of Relagent with the same LLM provider.
- **No arbitrary context extension** using MCP (Model Context Protocol). There is currently no way to control which data would be sent to 3rd party services.
- Use of a **shared secret** among devices. No per device authentication and access revocation yet.
- Only marginally tested setup and update routines with **focus on Linux**.

## License

Free and open source software. Released under [BSD 2-Clause License](license.txt).

Use it as you want. If you distribute or modify it, keep an easy discoverable reference to source and license.
