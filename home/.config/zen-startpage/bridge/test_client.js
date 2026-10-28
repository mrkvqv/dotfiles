const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
process.env.TZ = 'Europe/Warsaw';
const sandbox = {window:{ZEN_CALENDAR_TESTING:true},document:{querySelectorAll:()=>[]},URL,Intl,Date};
vm.runInNewContext(fs.readFileSync(path.join(__dirname,'calendar-client.js'),'utf8'),sandbox);
const api = sandbox.window.ZenCalendarTest;
const event = (id,start,end,extra={}) => ({id,title:id,start:new Date(start).toISOString(),end:new Date(end).toISOString(),allDay:false,calendarId:'calendar',...extra});
const events = [
  event('overnight','2026-10-19T23:00:00','2026-10-20T01:00:00'),
  event('midnightEnd','2026-10-19T22:00:00','2026-10-20T00:00:00'),
  event('zero','2026-10-20T12:00:00','2026-10-20T12:00:00'),
  event('allDay','2026-10-20T00:00:00','2026-10-21T00:00:00',{allDay:true,startDay:'2026-10-20',endDay:'2026-10-21'}),
  event('multiDay','2026-10-19T00:00:00','2026-10-22T00:00:00',{allDay:true,startDay:'2026-10-19',endDay:'2026-10-22'}),
  event('DST','2026-10-25T00:00:00','2026-10-26T00:00:00'),
  event('spanning','2026-10-19T12:00:00','2026-10-22T13:00:00'),
];
const ids = key => Array.from(api.eventsForDay({events},key),x=>x.id).sort();
assert.deepEqual(ids('2026-10-20'),['allDay','multiDay','overnight','spanning','zero']);
assert(!ids('2026-10-21').includes('allDay'));
assert(!ids('2026-10-22').includes('multiDay'));
assert(ids('2026-10-25').includes('DST'));
assert(!ids('2026-10-26').includes('DST'));
assert.equal(api.eventTime(events[0],'2026-10-20'),'до 01:00');
assert.equal(api.eventTime(events[6],'2026-10-20'),'Продолжается');
assert.equal(api.safeURL('javascript:alert(1)'),null);
assert.equal(api.safeURL('file:///etc/passwd'),null);
assert.equal(api.safeURL('https://example.com/meeting').host,'example.com');
assert.equal(api.safeColor('url(javascript:alert(1))'),'#b8b8ad');
assert.equal(api.safeColor('#aabbcc'),'#aabbcc');
console.log('PASS: exclusive all-day ends, overnight and zero-duration events, multi-day events, 25-hour DST day, continuation labels, safe URLs/colors.');
