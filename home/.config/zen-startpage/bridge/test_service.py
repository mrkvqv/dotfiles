#!/usr/bin/env python3
"""Exercise the real local bridge without printing event contents or credentials."""
from pathlib import Path
import json
import stat
import urllib.error
import urllib.request

HOME = Path.home()
CONFIG = HOME / 'Library/Application Support/ZenCalendarBridge/config.json'
config = json.loads(CONFIG.read_text())
base = 'http://127.0.0.1:' + str(config['port'])


def request(path, expected=200, authorized=True, method='GET', headers=None):
    values = dict(headers or {})
    if authorized:
        values['Authorization'] = 'Bearer ' + config['token']
    req = urllib.request.Request(base + path, method=method, headers=values)
    try:
        response = urllib.request.urlopen(req, timeout=8)
    except urllib.error.HTTPError as error:
        response = error
    assert response.status == expected, (path, response.status, expected)
    body = response.read()
    return response, json.loads(body) if body else {}


for path in [CONFIG, HOME / '.config/zen-startpage/calendar-bridge-config.js']:
    assert stat.S_IMODE(path.stat().st_mode) == 0o600

_, status = request('/v1/status')
assert status['access'] == 'granted', status['access']
request('/v1/status', 401, authorized=False)
request('/v1/status', 403, headers={'Origin':'https://example.com'})
request('/v1/status', 403, headers={'Host':'example.com'})
request('/v1/status', 405, method='POST')
request('/v1/unknown', 404)
request('/v1/pins', 401, authorized=False)
request('/v1/pins', 403, headers={'Origin':'https://example.com'})
_, pins = request('/v1/pins', headers={'Origin':'null'})
assert pins['source'] == 'Zen Essentials'
assert isinstance(pins['pins'], list)
for pin in pins['pins']:
    assert set(pin) == {'id','url','title','image','symbol','customIcon'}
    assert pin['url'].startswith(('https://','http://'))
print('PASS: authenticated Essentials snapshot; no full session or profile data returned.')
request('/v1/events?start=2026-02-30&end=2026-03-10', 400)
request('/v1/events?start=2026-01-01&end=2027-01-01', 400)
request('/v1/events?start=2026-10-20&end=2026-10-19', 400)
request('/v1/events?start=2026-10-01&end=2026-11-01&extra=true', 400)
response, _ = request('/v1/events', 204, authorized=False, method='OPTIONS', headers={
    'Origin':'null','Access-Control-Request-Method':'GET','Access-Control-Request-Headers':'authorization',
})
assert response.headers['Access-Control-Allow-Origin'] == 'null'
request('/v1/events', 403, authorized=False, method='OPTIONS', headers={
    'Origin':'https://example.com','Access-Control-Request-Method':'GET',
})
counts = []
for start, end in [('2026-09-28','2026-11-09'),('2026-01-01','2026-02-01'),('2027-01-01','2027-02-01')]:
    response, data = request('/v1/events?start='+start+'&end='+end, headers={'Origin':'null'})
    assert response.headers['Cache-Control'] == 'no-store'
    assert response.headers['Access-Control-Allow-Origin'] == 'null'
    assert len(data['calendars']) == status['calendarCount']
    calendar_ids = {calendar['id'] for calendar in data['calendars']}
    for event in data['events']:
        assert event['calendarId'] in calendar_ids
        assert all(key in event for key in ['start','end','title','notes','location','url','attendees','alarms','recurrence','allDay'])
    counts.append(len(data['events']))
print('PASS: Calendar access, private configuration, authentication, origin/Host restrictions, read-only methods, date limits, preflight, no-store responses, all calendars and event detail fields.')
print('Calendars:', status['calendarCount'], '; events in tested ranges:', counts)
