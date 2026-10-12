#!/usr/bin/env python3
"""Restore managed configuration files, backing up each existing file first."""
import argparse
import configparser
from datetime import datetime
import io
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
HOME = Path.home()
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--dry-run", action="store_true", help="Show the files that would be restored")
args = parser.parse_args()
subprocess.run(["/usr/bin/python3", str(ROOT / "scripts/check_secrets.py")], check=True)
backup = HOME / "config-backups" / datetime.now().strftime("%Y-%m-%d_%H-%M-%S_before-dotfiles-restore")
for name in json.loads((ROOT / "managed-files.json").read_text()):
    relative = Path(name)
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError(f"Invalid managed path: {name}")
    source = ROOT / "home" / relative
    target = HOME / relative
    if args.dry_run:
        print(name)
        continue
    if target.exists():
        saved = backup / relative
        saved.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(target, saved)
    content = source.read_text()
    if source.suffix == ".plist":
        content = content.replace("__HOME__", str(HOME))
    if name == ".config/qBittorrent/qBittorrent.ini" and target.exists():
        current = configparser.ConfigParser(interpolation=None, strict=False)
        current.optionxform = str
        current.read(target)
        current.read_string(content)
        result = io.StringIO()
        current.write(result, space_around_delimiters=False)
        content = result.getvalue()
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content)
    target.chmod(source.stat().st_mode & 0o777)
if not args.dry_run:
    print(f"Restored configuration files. Previous files: {backup}")
    print("Reload Ghostty with ⌘⇧, and open a new Fish shell. Restart Zed if necessary.")
    print("Desktop LaunchAgents are copied without loading them. Zen/Raycast snapshots are separate.")
