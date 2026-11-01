# Mac Dotfiles

Personal configuration for Fish, Bash, Zsh, Ghostty, Zed, GitHub CLI, Karabiner,
OpenCode, qBittorrent and Starship, plus macOS desktop assignment tools.
The **Midnight MacBook** theme in Zed is the color source for Ghostty.
The `ls` command runs the Homebrew-installed `nls` package directly.

## Contents

- `home/` — configuration files and scripts, preserving paths relative to the home directory.
- `snapshots/` — selected settings and extension lists for Zen, Raycast, Zed and T3 Code.
- `Brewfile` — the installed applications and utilities.
- `scripts/sync.py` — exports configuration using an explicit allowlist.
- `scripts/check_secrets.py` — checks the snapshot and staged files for credentials.
- `scripts/restore.py` — restores configuration and backs up existing files first.

History, cookies, passwords, tokens, accounts, databases, caches, `node_modules`,
downloaded extensions and backups are excluded from this repository.
The Raycast snapshot contains ordinary appearance settings and an extension list;
authentication, chats and extension data remain local.
The Zen snapshot contains selected persistent preferences, shortcuts, CSS and an
extension list, rather than a complete browser profile.

## Update the repository

```sh
cd ~/dotfiles
/usr/bin/python3 scripts/sync.py
/usr/bin/python3 scripts/check_secrets.py
git add home snapshots managed-files.json
git commit -m "Update device configuration"
git push
```

After cloning, enable the pre-commit check:

```sh
git config core.hooksPath .githooks
```

The check covers known token formats and sensitive configuration keys. Add new
configuration paths to `PATTERNS`, rather than exporting the entire home directory.

## Restore configuration

Preview the managed files:

```sh
/usr/bin/python3 scripts/restore.py --dry-run
```

Restore them:

```sh
/usr/bin/python3 scripts/restore.py
```

Existing files are backed up to `~/config-backups/<date>_before-dotfiles-restore`.
qBittorrent settings are merged with the existing configuration, preserving local
passwords and cookies. After restoring, open a new terminal tab, reload Ghostty
with **Cmd+Shift+,**, and restart Zed if needed.

Zen and Raycast snapshots are restored separately through their applications.
When transferring Zen shortcuts, close the browser and use the active profile
listed in `~/.config/zen/installs.ini`. Complete profiles are not transferred.

## Automatic directory shortcuts

Type `!` before a directory name, then press Space or Enter. Fish expands it to
`cd` with the full path under your home directory. For example, `!sem5` becomes
`cd ~/Documents/sem5`. Enter executes the command; Space lets you inspect and edit it first.

Directories are discovered when the abbreviation expands. New or renamed folders,
including those created in Finder or Zed, are available immediately. No generated
`abbr` entries need to be saved or committed.

Regular commands, Fish functions and manual abbreviations take precedence.
Missing or ambiguous directory names produce a command that prints an English
error after Enter, without mixing the error into the editable command line.
For duplicate names, use a full path or a manual abbreviation. Automatic directory
navigation requires the `!` prefix.

The search excludes hidden directories, `Library`, `Applications`, `config-backups`,
`node_modules`, `target`, `build`, `dist`, `vendor`, `venv`, `__pycache__`, `Pods`,
`DerivedData`, and application or media-library bundles. Symbolic links are not traversed.
Automatic names may contain letters, digits, `_`, `-` and dots, and must start with
a letter, digit or `_`. Names containing spaces can use manual abbreviations.

Configuration: `conf.d/30-auto-directories.fish`.
Implementation: `functions/__auto_directory.fish`.
Set `auto_directory_root` to change the search root.
Existing abbreviations in `config.fish` are preserved.

## Bash

`home/.bashrc` configures interactive Bash. `home/.bash_profile` loads `~/.profile`
and `~/.bashrc` for login sessions. Interactive sessions use Homebrew Bash 5;
the system `/bin/bash` remains available. Fish is the primary shell, and its
`bash` function starts `/opt/homebrew/bin/bash`.

- Starship shares the Fish theme: current directory, Git status and command duration.
  Bash displays a bold shell label before the directory; Fish omits it.
- Up and Down search history by command prefix; `Ctrl+R` searches by text.
- ble.sh provides muted suggestions from history and completions. `Tab` accepts a
  visible suggestion or completes the command; `Shift+Tab` opens completion.
- History is appended to `~/.bash_history` and shared between tabs at the next
  prompt. Consecutive duplicates and commands beginning with a space are not saved.
- `ls` runs `nls`; `ll` shows a detailed listing, and `la` includes hidden files.
- `z name` uses Zoxide to find a familiar directory; `mkcd path` creates and enters one.
- `docs`, `config`, `dotfiles`, `work`, `rust`, `net`, `..` and `...` navigate to directories.
- `zed` without arguments opens the current directory; other arguments are passed to Zed.

These settings apply to Bash. ble.sh settings live in `home/.blerc`; the package
itself is installed once at `~/.local/share/blesh` and is not tracked in Git.
Without ble.sh, or when using system Bash, normal Readline remains available.

Install on a new Mac after restoring the configuration:

```sh
brew install bash
bash ~/dotfiles/scripts/install_blesh.sh
```

Starship, Zoxide and ble.sh are initialized once. Sourcing `.bashrc` again does not
duplicate handlers. Fish's `!` directory shortcut feature is not installed in Bash;
use `z` there instead.

## Shared Fish and Bash colors

The input-highlighting palette lives in `home/.config/shell/colors.conf`;
the active file is `~/.config/shell/colors.conf`. It defines colors for commands,
parameters, paths, suggestions, errors, comments, keywords, options, quoted text,
operators and escapes. Values are six-digit RGB hex strings without `#`.

Fish reads the palette in `conf.d/40-theme.fish`; Bash/ble.sh reads it in `.blerc`.
Those files retain the shell-specific mappings and behavior. New sessions pick up
palette changes automatically. To refresh an existing session:

```sh
# Fish
source ~/.config/fish/conf.d/40-theme.fish

# Bash with ble.sh
source ~/.blerc
```

There is no need to source `.bashrc` just to update colors. The palette is data,
not executable shell code.

## Desktop switching with Karabiner

`Cmd+1` through `Cmd+5` invoke `~/.local/bin/desktop-switch`, which sends a normal
desktop-switching gesture to Dock. It does not switch Spaces directly through
WindowServer, which previously disrupted menu bar updates.
`Ctrl+1` through `Ctrl+5` are not required; the system shortcuts remain disabled.
Other Karabiner rules are preserved. Cmd combinations with extra modifiers,
such as Shift, are not intercepted by this rule.

The helper uses the InstantSpaceSwitcher core pinned to a specific commit and is
intended for one active display. It does not install the upstream application.
The wrapper source and build script are tracked; the built binary and the
dependency's MIT license remain local. Accessibility permission is required to
send gestures. Check compatibility after macOS updates.

Build after restoring:

```sh
bash ~/dotfiles/scripts/install_desktop_switch.sh
```

## Themes and desktop assignments

### Midnight MacBook

A shared plum palette for Zed, Ghostty and T3 Code: background `#19121d`, text
`#e8dfea` and lilac accents `#c7a4d5`. Syntax highlighting separates violet, blue,
pink and ice-blue tones. Zed's title bar uses a uniform dark background.

The T3 theme is stored separately from application data:

```sh
~/.t3/bin/t3 theme set midnight-macbook
```

`home/.t3/userdata/themes/` contains only the theme JSON.
`snapshots/t3/appearance.json` contains only the theme name, internal glass opacity
and contrast. T3 credentials, chats and databases are not exported.

### Zen Startpage

The standalone source project is at **`~/projects/zen-startpage`**, with a preview,
installer and local integration documentation. This repository keeps an installed
snapshot at `home/.config/zen-startpage/` for restoring this Mac.

Zen and its home page currently use the black theme. The optional plum home-page
theme and woven texture are preserved in `midnight-macbook.css`, but are not enabled
by default. A local EventKit helper reads Apple Calendar; Essentials are read from
Zen's saved session. BroTab selects existing pinned tabs, and the optional Home
command reuses the home tab.
See [the bridge documentation](home/.config/zen-startpage/bridge/README.md) for setup
and limitations.

`calendar-bridge-config.js`, which contains the local token, is excluded from both
export and Git. Helper source is tracked; personal events and browser sessions are not.

### Updating colors

Edit `~/.config/zed/themes/midnight-macbook.json`, run `theme-sync`, then press
**Cmd+Shift+,** in Ghostty. `nls` controls the layout of `ls` output; Ghostty renders
its ANSI colors using the active palette.

### Desktop Assignments

Source: `home/.config/desktop-assignments-sync.swift`.
Build after restoring:

```sh
mkdir -p ~/.local/bin
swiftc -O ~/.config/desktop-assignments-sync.swift -o ~/.local/bin/desktop-assignments-sync
```

LaunchAgent files use `__HOME__`, which the restore script replaces with the actual
home directory. The script does not automatically load agents or change desktop
assignments. See `home/.config/desktop-assignments.README.md` for details.

## Checks

```sh
/usr/bin/python3 scripts/check_secrets.py
/bin/bash -n home/.bashrc home/.bash_profile home/.blerc scripts/install_blesh.sh
fish -n home/.config/fish/config.fish home/.config/fish/conf.d/*.fish home/.config/fish/functions/*.fish
```

The credential check looks for known token formats and sensitive configuration keys.
See `CLEANUP.md` for the configuration cleanup report.
