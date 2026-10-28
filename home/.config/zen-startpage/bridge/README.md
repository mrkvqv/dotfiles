# Apple Calendar → Zen startpage

The personal `Zen Calendar Bridge.app` reads calendars through Apple's EventKit.
It makes no changes to events. It queries the 42 days currently visible in the
browser calendar, including occurrences of recurring events and all accessible
calendars. Browsing another month queries that range on demand.

The page shows event markers, a selected-day agenda, and expandable event details.
Each event expands as one rounded card, with its details inside the same border.
Expansion and closing use reversible eased height/opacity motion. The details
scroll inside the card; soft blur/fade overlays mark only edges with more content.
The frame is painted above the scroll/filter layers, and the blur viewport stays
stationary while the inner text animates, preventing rounded-corner flicker.
ResizeObserver and passive scroll events update the edges, without polling.
The agenda reserves a fixed height in every state, so switching days does not
move the clock, bookmarks, or month grid. Long event lists and details scroll
inside that area. The compact Calendars control in the agenda header opens a
floating list without changing layout; Escape or clicking outside dismisses it.
Disclosure arrows are non-selectable SVG icons. Day changes and disclosures use
short, eased animations;
the system's Reduce Motion preference disables them.
It refreshes every 30 seconds while visible, on window focus, and with Refresh.
System Calendar must have synchronized the account for its events to be available.
The same local helper reads Zen's saved `zen-sessions.jsonlz4` and returns only
the upper Essentials through `/v1/pins`. Cards follow their saved order, pinned
URLs, and cached icons, including additions and removals. The page checks on load,
focus, and every 30 seconds; quitting Zen flushes changes for the next launch.
Other tabs, history, session storage, and profile paths are not returned or copied
into dotfiles. Known services retain their larger embedded logos; custom icons
and new sites use Zen's saved icons, with a letter fallback if no icon is cached.
The signed [BroTab add-on](https://addons.mozilla.org/firefox/addon/brotab/) and
`tab-controller.py` switch directly to an existing visible pinned tab in the active
window. A normal card click is intercepted before navigation: no intermediate
tab, URL change, or site reload. Matching uses the site hostname and port; the
first matching pinned tab wins. Modifier clicks retain normal link behavior.
Missing pins produce a short notice rather than creating duplicate tabs.

The Home button uses a local browser-chrome command in `zen-home.js`. It searches
all Zen spaces in the current window and selects the existing local homepage
without opening, closing, or reloading tabs. If the homepage is absent, it creates
one and reuses it, including during the initial load. The home view follows the
active space and stays hidden in the sidebar through `userChrome.css`. Other
site tabs keep their URLs and positions. Legacy/manual copies of the exact local
homepage are normalized by the native command and after session restoration.
The command is installed automatically by an AutoConfig observer on browser
startup; it makes no local HTTP request. Changing the configured homepage later
restores the native Home behavior for that different URL.
EventKit does not expose event attachments; open Apple Calendar for attachments
and editing. Reminders are a separate macOS data store and are not exported here.

## Install / restore

1. Run `python3 ~/.config/zen-startpage/bridge/install.py` (Xcode command line tools).
2. Open `~/Applications/Zen Calendar Bridge.app` and allow Calendar access.
3. Enable the generated LaunchAgent:
   `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.zen-calendar-bridge.plist`.
4. Install the signed BroTab add-on in Zen and run
   `python3 ~/.config/zen-startpage/bridge/install-tab-controller.py`.
5. Run `python3 ~/.config/zen-startpage/bridge/install-home-button.py` for the
   default profile (or pass `--profile /path/to/profile`). macOS may require
   App Management permission for the application running the installer.
6. Restart Zen and use Home. The source script is copied to
   `<profile>/chrome/zen-home.js`; the existing sidebar CSS hides that view.

The Home installer adds only `Contents/Resources/mrkvqv-home.cfg` and
`Contents/Resources/defaults/pref/mrkvqv-home.js` inside Zen. The local AutoConfig
runs with browser-chrome privileges (`general.config.sandbox_enabled=false`) and
loads exactly the owner-only profile script through a chrome-only resource alias.
It loads no remote scripts. A full replacement/reinstallation of Zen may remove
these files; rerun the installer and restart. To remove the loader, run the same
installer with `--remove`, then restart. Troubleshoot Mode skips this loader.

The installer creates the LaunchAgent and owner-only local configuration. The
bridge app starts at login. Its Calendar permission can be managed in macOS
System Settings → Privacy & Security → Calendars.

## Local privacy and access

- Calendar Bridge listens on `127.0.0.1:8766`; the tab controller uses
  `127.0.0.1:8767`. Both bind only to loopback. BroTab starts its native host
  with Zen and stops it on browser exit; it needs no separate LaunchAgent.
- The tab controller shares the private bearer token and origin/Host checks.
  `POST /v1/activate-pin` accepts a site URL, queries visible pinned tabs and
  sets only the matching tab’s `active` flag. It opens or closes no tabs; Home
  routing lives entirely inside the browser UI command.
  It exposes no tab list and accepts no arbitrary native commands.
  The installed BroTab package requests tabs, activeTab, all-URLs, and native
  messaging permissions; Mozilla signature checking stays enabled.
- Requires a random bearer token for data; rejects foreign website origins and
  unexpected Host headers. The only allowed browser origin is the local file's
  `null` origin. Preflight responses contain no calendar data.
- Event responses use `Cache-Control: no-store`. Events are not stored on disk.
- The token is in `~/Library/Application Support/ZenCalendarBridge/config.json`
  and `~/.config/zen-startpage/calendar-bridge-config.js` (both mode 0600).
  Neither is part of the dotfiles snapshot. Reinstalling preserves the token.
- Only code, the static page, and installation instructions belong in dotfiles.
  Do not copy event responses or the private configuration into the repository.

To stop the helper, use `launchctl bootout gui/$(id -u)/local.zen-calendar-bridge`.
Calendar data and accounts remain in Apple Calendar.
