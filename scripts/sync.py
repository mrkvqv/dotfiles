#!/usr/bin/env python3
"""Export configuration files, with an explicit allowlist and no application data."""
import configparser
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
HOME = Path.home()
PATTERNS = [
    ".gitconfig", ".zshrc", ".zshenv", ".profile", ".bashrc", ".bash_profile", ".blerc",
    ".config/fish/config.fish",
    ".config/fish/conf.d/*.fish", ".config/fish/functions/*.fish",
    ".config/ghostty/config", ".config/ghostty/*.py", ".config/ghostty/themes/*",
    ".config/theme_utils.py", ".config/starship.toml", ".config/shell/colors.conf",
    ".config/zed/settings.json", ".config/zed/keymap.json", ".config/zed/themes/*.json",
    ".config/gh/config.yml", ".config/karabiner/karabiner.json", ".config/karabiner/desktop-switch.swift",     ".config/lsd/config.yaml",
    ".config/zen-startpage/*.html",
    ".config/opencode/opencode.json", ".config/opencode/package.json", ".config/opencode/package-lock.json",
    ".config/desktop-assignments.json", ".config/desktop-assignments-sync.swift",
    ".config/desktop-assignments.README.md",
    "Library/LaunchAgents/local.desktop-assignments.*.plist",
]


def json_file(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def ini():
    result = configparser.ConfigParser(interpolation=None, strict=False)
    result.optionxform = str
    return result


def zen_profile():
    # macOS default location first, then Linux/XDG fallback.
    candidates = [
        HOME / "Library/Application Support/zen/profiles.ini",
        HOME / ".config/zen/installs.ini",
    ]
    for ini_path in candidates:
        if not ini_path.is_file():
            continue
        base = ini_path.parent
        config = ini()
        config.read(ini_path)
        for section in config.sections():
            if config.has_option(section, "Default"):
                relative = config.get(section, "Default")
                profile = (base / relative).resolve()
                if profile.is_dir():
                    return profile
    return None


def export_zen():
    profile = zen_profile()
    if profile is None:
        return
    target = ROOT / "snapshots/zen"
    target.mkdir(parents=True, exist_ok=True)
    prefixes = ("zen.view.", "zen.swipe.", "zen.tab-unloader.", "zen.library.media.")
    names = {
        "toolkit.legacyUserProfileCustomizations.stylesheets", "browser.theme.toolbar-theme",
        "browser.tabs.warnOnClose", "browser.tabs.warnOnOpen", "browser.tabs.loadInBackground",
        "browser.startup.page", "browser.startup.homepage", "browser.urlbar.suggest.searches", "browser.urlbar.suggest.history",
        "zen.widget.macos.window-vibrancy",
        "widget.macos.native-popovers", "zen.theme.acrylic-sidebar",
        "zen.theme.acrylic-urlbar", "browser.tabs.allow_transparent_browser",
        "browser.urlbar.suggest.bookmark", "privacy.clearOnShutdown_v2.formdata",
        "privacy.globalprivacycontrol.enabled", "privacy.donottrackheader.enabled",
        "privacy.trackingprotection.enabled", "privacy.trackingprotection.pbmode.enabled",
    }
    preferences = {}
    for line in (profile / "prefs.js").read_text().splitlines():
        match = re.fullmatch(r'user_pref\("([^"\\]+)", (.*)\);', line)
        if match and (match[1] in names or match[1].startswith(prefixes)):
            value = json.loads(match[2])
            if isinstance(value, (bool, int, float, str)):
                preferences[match[1]] = value
    content = "// Selected persistent preferences; no browsing history or account data.\n"
    for key, value in sorted(preferences.items()):
        content += f"user_pref({json.dumps(key)}, {json.dumps(value)});\n"
    (target / "user.js").write_text(content)
    for name in ("zen-keyboard-shortcuts.json", "zen-themes.json", "chrome/zen-themes.css", "chrome/userContent.css", "chrome/userChrome.css"):
        source = profile / name
        if source.exists():
            output = target / name
            output.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, output)
    extensions = json.loads((profile / "extensions.json").read_text()).get("addons", [])
    json_file(target / "extensions.json", [
        {"id": item.get("id"), "name": item.get("defaultLocale", {}).get("name"), "version": item.get("version")}
        for item in extensions if item.get("type") == "extension" and item.get("active")
    ])


def export_raycast():
    target = ROOT / "snapshots/raycast"
    extensions = []
    for source in sorted((HOME / ".config/raycast/extensions").glob("*/package.json")):
        data = json.loads(source.read_text())
        extensions.append({key: data.get(key) for key in ("name", "title", "version") if data.get(key) is not None})
    json_file(target / "extensions.json", extensions)
    process = subprocess.run(["/usr/bin/defaults", "export", "com.raycast.macos", "-"], capture_output=True)
    if process.returncode == 0:
        data = plistlib.loads(process.stdout)
        allowed = {"raycastPreferredWindowMode", "raycastShouldFollowSystemAppearance", "raycast_ShowWindowsImmediately", "useHyperKeyIcon"}
        json_file(target / "preferences.json", {key: value for key, value in data.items() if key in allowed and isinstance(value, (str, bool, int))})


def export_qbittorrent():
    source = HOME / ".config/qBittorrent/qBittorrent.ini"
    if not source.exists():
        return
    data = ini()
    data.read(source)
    for section in data.sections():
        for key in list(data[section]):
            # Session\Port is a setting; passwords, cookies and path history are not exported.
            if re.search(r"password|token|secret|apikey|api_key|cookies|history|lastaddpath", key, re.I):
                data.remove_option(section, key)
    target = ROOT / "home/.config/qBittorrent/qBittorrent.ini"
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("w") as file:
        data.write(file, space_around_delimiters=False)


def main():
    previous = ROOT / "managed-files.json"
    if previous.exists():
        for name in json.loads(previous.read_text()):
            target = ROOT / "home" / name
            if target.is_relative_to(ROOT / "home") and target.is_file():
                target.unlink()
    for pattern in PATTERNS:
        for source in sorted(HOME.glob(pattern)):
            if not source.is_file() or source.is_symlink():
                continue
            relative = source.relative_to(HOME)
            target = ROOT / "home" / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if source.suffix == ".plist":
                target.write_text(source.read_text().replace(str(HOME), "__HOME__"))
            else:
                shutil.copy2(source, target)
    export_qbittorrent()
    export_zen()
    export_raycast()
    extensions = HOME / "Library/Application Support/Zed/extensions/installed"
    json_file(ROOT / "snapshots/zed/extensions.json", sorted(path.name for path in extensions.iterdir() if path.is_dir()))
    files = sorted(str(path.relative_to(ROOT / "home")) for path in (ROOT / "home").rglob("*") if path.is_file())
    json_file(previous, files)
    print(f"Exported {len(files)} configuration files plus application preference snapshots.")


if __name__ == "__main__":
    main()
