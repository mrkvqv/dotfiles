# Desktop Assignments

`~/.config/desktop-assignments.json` is the active configuration for the
`local.desktop-assignments.sync` user LaunchAgent.

Map application bundle identifiers to desktop numbers. Identifiers are matched
in lowercase. Desktop numbers refer to ordinary desktops in their current order;
native fullscreen spaces are excluded. Keep automatic Spaces reordering disabled.

Save the JSON file to apply changes. Assignments are also applied when you sign
in, or when you run the command below. There is no periodic enforcement. The
agent resolves current Space UUIDs instead of retaining old UUIDs and preserves
assignments for applications not listed in the file.

When an assignment differs, the agent updates `com.apple.spaces` and restarts
Dock to apply it. Dock may briefly disappear and an open Mission Control view or
Dock menu will close. When nothing differs, it makes no changes and does not
restart Dock. This does not continuously move existing application windows.

Invalid JSON, duplicate case-insensitive identifiers, unavailable desktop numbers,
or multiple active displays cause an error without changing any assignments.
Removing an application from JSON stops managing its assignment but does not
remove its existing macOS assignment; use Dock's Assign To menu to remove it.

Apply the configuration manually:

```sh
~/.local/bin/desktop-assignments-sync
```

Check the active assignments without changing them:

```sh
~/.local/bin/desktop-assignments-sync --check
```

Application log: `~/Library/Logs/desktop-assignments-sync.log`

## Passive Diagnostics

`local.desktop-assignments.diagnostics` watches the persisted Spaces preferences
and the JSON configuration. It logs changes to managed assignments and desktop
UUIDs/order, without changing macOS settings or restarting Dock. It uses no timer
and deduplicates unchanged snapshots. A lost assignment stays lost until the next
sign-in, JSON save, or manual application.

Preference writes may be delayed or coalesced by macOS, so this is diagnostic
evidence of persisted changes, not a complete trace of every in-memory transition
or proof of which process caused a reset.

Diagnostic log: `~/Library/Logs/desktop-assignments-diagnostics.log`
Last snapshot: `~/.local/state/desktop-assignments-diagnostics.json`

Capture a diagnostic snapshot manually:

```sh
~/.local/bin/desktop-assignments-sync --diagnose
```

## Disable Or Enable

Disable automatic application and passive diagnostics:

```sh
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/local.desktop-assignments.sync.plist
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/local.desktop-assignments.diagnostics.plist
```

Enable it again:

```sh
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.desktop-assignments.sync.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.desktop-assignments.diagnostics.plist
```

The source is `~/.config/desktop-assignments-sync.swift`. Changes to the source
require recompilation; changes to the JSON do not.
