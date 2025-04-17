#!/usr/bin/env python

import os

import gradio as gr
from agents import get_agent
from models import get_model

SERVER_NAME = os.environ.get("SERVER_NAME", None)
SERVER_PORT = int(os.environ.get("SERVER_PORT", 7860))

model = get_model(use_case="multi_free")

agent = get_agent(model=model)


def chat_text(message: str, history: list[dict]) -> str:
    return agent.run(task=message)


def chat_multimodal(message: dict, history: list[dict]) -> str:
    generator = agent.run(task=message["text"], images=message["files"])
    return generator.to_string()


interface = gr.ChatInterface(
    fn=chat_multimodal,
    type="messages",
    multimodal=True,
    cache_mode="lazy",
    # textbox=gr.MultimodalTextbox(file_count="multiple", file_types=["image"], sources=["upload", "microphone"]),
    title="Simple Agent",
    description="A chat agent that can answer questions and run web searches.",
)

interface.launch(
    server_name=SERVER_NAME,
    server_port=SERVER_PORT,
)
