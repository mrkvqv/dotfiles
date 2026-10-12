#!/usr/bin/env python3
"""Check the tracked configuration snapshot without printing any secret values."""
from pathlib import Path
import re
import sys
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PATTERNS = [
    re.compile(r"(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,}|sk-[A-Za-z0-9_-]{20,})"),
    re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    re.compile(r"https?://[^\s/@:]+:[^\s/@]+@"),
]
FIELDS = r"api[_-]?key|oauth[_-]?token|access[_-]?token|refresh[_-]?token|token|password|secret|authorization"
SECRET_KEY = re.compile(r'''(?im)(?:["'](?:''' + FIELDS + r''')["']|^\s*(?:''' + FIELDS + r'''))\s*[:=]\s*["']?([^\s,"'}]+)''')
FORBIDDEN = {"hosts.yml", "fish_variables", "auth.json", "aster-endpoint.json", "logins.json", "cookies.sqlite", "prefs.js", "qBittorrent-data.ini"}
problems = []
files = {str(path.relative_to(ROOT)): path.read_text() for directory in (ROOT / "home", ROOT / "snapshots") for path in directory.rglob("*") if path.is_file()}
if (ROOT / ".git").exists():
    staged = subprocess.check_output(["git", "diff", "--cached", "--name-only", "--diff-filter=ACM", "-z"], cwd=ROOT).decode().split("\0")
    for name in filter(None, staged):
        files[name] = subprocess.check_output(["git", "show", f":{name}"], cwd=ROOT).decode()
for name, text in files.items():
    relative = Path(name)
    if relative.name in FORBIDDEN or "node_modules" in relative.parts:
        problems.append(f"Forbidden application-data file: {relative}")
        continue
    for number, line in enumerate(text.splitlines(), 1):
        key = SECRET_KEY.search(line)
        if any(pattern.search(line) for pattern in PATTERNS) or (key and key[1].lower() not in {"null", "none", "false", "<redacted>"}):
            problems.append(f"Possible secret: {relative}:{number}")
if problems:
    print("\n".join(problems), file=sys.stderr)
    sys.exit(1)
print("No credential values or forbidden application-data files found in the snapshot.")
