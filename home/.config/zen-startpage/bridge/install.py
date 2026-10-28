#!/usr/bin/env python3
"""Build a personal, read-only Calendar bridge. Credentials stay outside dotfiles."""
from pathlib import Path
import json
import os
import plistlib
import secrets
import subprocess

HOME = Path.home()
ROOT = Path(__file__).resolve().parent
APP = HOME / 'Applications/Zen Calendar Bridge.app'
CONTENTS = APP / 'Contents'
EXECUTABLE = CONTENTS / 'MacOS/ZenCalendarBridge'
IDENTIFIER = 'local.mrkvqv.ZenCalendarBridge'
STATE = HOME / 'Library/Application Support/ZenCalendarBridge'


def private_write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, 'w') as stream:
        stream.write(text)
    path.chmod(0o600)


def main():
    EXECUTABLE.parent.mkdir(parents=True, exist_ok=True)
    info = {
        'CFBundleIdentifier': IDENTIFIER,
        'CFBundleName': 'Zen Calendar Bridge',
        'CFBundleDisplayName': 'Zen Calendar Bridge',
        'CFBundleExecutable': EXECUTABLE.name,
        'CFBundlePackageType': 'APPL',
        'CFBundleVersion': '1',
        'CFBundleShortVersionString': '1.0',
        'LSUIElement': True,
        'LSMinimumSystemVersion': '14.0',
        'NSCalendarsFullAccessUsageDescription': 'Показ событий Apple Calendar на вашей локальной стартовой странице Zen. События не покидают Mac.',
        'NSCalendarsUsageDescription': 'Показ событий Apple Calendar на вашей локальной стартовой странице Zen.',
    }
    (CONTENTS / 'Info.plist').write_bytes(plistlib.dumps(info))
    build = EXECUTABLE.with_name(EXECUTABLE.name + '.new')
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library', '-O', '-target', 'arm64-apple-macosx14.0',
                    '-framework', 'AppKit', '-framework', 'EventKit', '-framework', 'Network',
                    '-lcompression', str(ROOT / 'ZenPins.swift'),
                    str(ROOT / 'CalendarBridge.swift'), '-o', str(build)], check=True)
    os.replace(build, EXECUTABLE)
    subprocess.run(['codesign', '--force', '--sign', '-', '--identifier', IDENTIFIER, str(APP)], check=True)
    STATE.mkdir(parents=True, exist_ok=True)
    STATE.chmod(0o700)
    config_path = STATE / 'config.json'
    config = json.loads(config_path.read_text()) if config_path.exists() else dict(port=8766, token=secrets.token_urlsafe(32))
    private_write(config_path, json.dumps(config) + '\n')
    client = dict(baseURL='http://127.0.0.1:' + str(config['port']), token=config['token'])
    private_write(ROOT.parent / 'calendar-bridge-config.js', 'window.ZEN_CALENDAR_BRIDGE = Object.freeze(' + json.dumps(client) + ');\n')
    logs = HOME / 'Library/Logs/ZenCalendarBridge'
    logs.mkdir(parents=True, exist_ok=True)
    agent = {
        'Label': 'local.zen-calendar-bridge',
        'ProgramArguments': [str(EXECUTABLE)],
        'RunAtLoad': True,
        'KeepAlive': True,
        'ThrottleInterval': 10,
        'ProcessType': 'Interactive',
        'LimitLoadToSessionType': 'Aqua',
        'StandardOutPath': str(logs / 'service.log'),
        'StandardErrorPath': str(logs / 'service-error.log'),
    }
    agents = HOME / 'Library/LaunchAgents'
    agents.mkdir(parents=True, exist_ok=True)
    (agents / 'local.zen-calendar-bridge.plist').write_bytes(plistlib.dumps(agent))
    print('Built Zen Calendar Bridge. Local configuration created with owner-only permissions.')
    print('Open the app once to grant macOS Calendar access; then enable its LaunchAgent.')


if __name__ == '__main__':
    main()
