"""Read and validate the shared Midnight MacBook color palette."""
import json
from pathlib import Path
import re

CONFIG_ROOT = Path(__file__).resolve().parent
THEME_NAME = "Midnight MacBook"


def load_style():
    data = json.loads((CONFIG_ROOT / "zed/themes/midnight-macbook.json").read_text())
    return next(theme["style"] for theme in data["themes"] if theme["name"] == THEME_NAME)


def color(style, key, fallback=None):
    value = style.get(key, fallback)
    if not isinstance(value, str) or not re.fullmatch(r"#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?", value):
        if fallback is not None:
            return fallback
        raise ValueError(f"Invalid theme color: {key}")
    return value


def ansi_color(value, bold=False):
    red, green, blue = (int(value[index:index + 2], 16) for index in (1, 3, 5))
    return f"\033[{'1;' if bold else ''}38;2;{red};{green};{blue}m"
