# Relatable Agentic Minion

A simple yet helpful set of AI powered tool for daily usage.

## Usage

Create a `.env` file from `.env.tempalte` and set relevant variables.

Then build and run the container:

```
bin/server-build.py
podman run --rm --publish 3000:7860 relagent
```

Now you can access the chat via `http://localhost:3000`.
