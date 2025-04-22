#!/usr/bin/env python

import gradio as gr
from agents import get_agent
from models import get_model
from settings import get_setting, get_setting_int

model = get_model(use_case="free")

agent = get_agent(model=model)


def chat_text(message: str, history: list[dict]) -> str:
    return agent.run(task=message)


def chat_multimodal(message: dict, history: list[dict]) -> str:
    generator = agent.run(task=message["text"], images=message["files"])
    return generator.to_string()


interface = gr.ChatInterface(
    fn=chat_text,
    type="messages",
    multimodal=False,
    cache_mode="lazy",
    # textbox=gr.MultimodalTextbox(file_count="multiple", file_types=["image"], sources=["upload", "microphone"]),
    title="Simple Agent",
    description="A chat agent that can answer questions and run web searches.",
)

if __name__ == "__main__":
    address = get_setting('server', 'address')
    port = get_setting_int('server', 'port', default=7860)
    print(
        f"Starting server on {address if address else '<default>'}:{port if port else '<default>'}..."
    )
    interface.launch(
        server_name=address,
        server_port=port,
    )
