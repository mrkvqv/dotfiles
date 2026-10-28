#!/usr/bin/env python3
"""Register the narrow native host used by the signed BroTab extension."""
from pathlib import Path
import json

root = Path(__file__).resolve().parent
host = root / 'tab-controller.py'
target = Path.home() / 'Library/Application Support/Mozilla/NativeMessagingHosts/brotab_mediator.json'
if target.exists():
    existing = json.loads(target.read_text())
    if existing.get('path') != str(host):
        raise SystemExit('An existing BroTab native host is already configured; it was not overwritten.')
host.chmod(0o700)
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(json.dumps({
    'name': 'brotab_mediator',
    'description': 'Activate existing Zen pinned tabs from the personal home page',
    'path': str(host),
    'type': 'stdio',
    'allowed_extensions': ['brotab_mediator@example.org'],
}, indent=2) + '\n')
target.chmod(0o600)
print('Registered the local pinned-tab controller. Browser signature checks are unchanged.')
