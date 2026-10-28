(() => {
  const configuration = window.ZEN_CALENDAR_BRIDGE;
  const keyFor = value => [value.getFullYear(), String(value.getMonth() + 1).padStart(2, '0'), String(value.getDate()).padStart(2, '0')].join('-');
  const parseDay = key => { const [y,m,d] = key.split('-').map(Number); return new Date(y,m-1,d); };
  const nextDay = key => { const d = parseDay(key); return new Date(d.getFullYear(),d.getMonth(),d.getDate()+1); };
  const timeFormat = new Intl.DateTimeFormat('ru-RU',{hour:'2-digit',minute:'2-digit',hour12:false});
  const dayFormat = new Intl.DateTimeFormat('ru-RU',{weekday:'long',day:'numeric',month:'long'});
  const dateTimeFormat = new Intl.DateTimeFormat('ru-RU',{dateStyle:'medium',timeStyle:'short'});
  const fullDayFormat = new Intl.DateTimeFormat('ru-RU',{dateStyle:'long'});
  const safeColor = value => /^#[0-9a-f]{6}$/i.test(value || '') ? value : '#b8b8ad';

  function eventsForDay(payload, key) {
    const start = parseDay(key).getTime(), end = nextDay(key).getTime();
    return payload.events.filter(event => {
      if (event.allDay) return event.startDay <= key && (event.endDay > key || event.startDay === key && event.endDay === event.startDay);
      const eventStart = Date.parse(event.start), eventEnd = Date.parse(event.end);
      return eventStart < end && (eventEnd > start || eventStart === eventEnd && eventStart >= start);
    }).sort((a,b) => Number(b.allDay)-Number(a.allDay) || Date.parse(a.start)-Date.parse(b.start) || a.title.localeCompare(b.title,'ru'));
  }

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined && text !== null) node.textContent = String(text);
    return node;
  }

  function chevron(className = '') {
    const svg = document.createElementNS('http://www.w3.org/2000/svg','svg');
    for (const [name,value] of Object.entries({viewBox:'0 0 24 24',fill:'none',stroke:'currentColor','stroke-width':'1.6','stroke-linecap':'round','stroke-linejoin':'round','aria-hidden':'true',focusable:'false',class:'disclosure-chevron ' + className})) svg.setAttribute(name,value);
    const path = document.createElementNS('http://www.w3.org/2000/svg','path');
    path.setAttribute('d','m6 9 6 6 6-6');
    svg.append(path);
    return svg;
  }

  function safeURL(value) {
    try { const parsed = new URL(value); return ['https:','http:'].includes(parsed.protocol) ? parsed : null; }
    catch { return null; }
  }

  function eventTime(event, key) {
    if (event.allDay) return 'Весь день';
    const start = new Date(event.start), end = new Date(event.end);
    if (start.getTime() === end.getTime()) return timeFormat.format(start);
    if (start < parseDay(key) && end >= nextDay(key)) return 'Продолжается';
    if (start < parseDay(key)) return 'до ' + timeFormat.format(end);
    if (end > nextDay(key)) return 'с ' + timeFormat.format(start);
    return timeFormat.format(start) + '–' + timeFormat.format(end);
  }

  function personName(person) {
    if (!person) return '';
    if (person.name) return person.name;
    try { return decodeURIComponent((person.url || '').replace(/^mailto:/i,'')); }
    catch { return person.url || ''; }
  }

  function recurrenceText(rule) {
    const single = ['Каждый день','Каждую неделю','Каждый месяц','Каждый год'];
    const units = [['день','дня','дней'],['неделю','недели','недель'],['месяц','месяца','месяцев'],['год','года','лет']];
    const n = rule.interval, last = n % 10, hundred = n % 100;
    const form = hundred >= 11 && hundred <= 14 ? 2 : last === 1 ? 0 : last >= 2 && last <= 4 ? 1 : 2;
    let label = n === 1 ? (single[rule.frequency] || 'Повторяется') : 'Раз в ' + n + ' ' + (units[rule.frequency]?.[form] || 'периодов');
    if (rule.daysOfWeek?.length) label += ', ' + rule.daysOfWeek.map(value=>['','вс','пн','вт','ср','чт','пт','сб'][value.day]).filter(Boolean).join(', ');
    if (rule.daysOfMonth?.length) label += ', числа: ' + rule.daysOfMonth.join(', ');
    if (rule.end?.date) label += ', до ' + fullDayFormat.format(new Date(rule.end.date));
    if (rule.end?.count) label += ', ' + rule.end.count + ' повторений';
    return label;
  }

  document.querySelectorAll('.scene').forEach(root => {
    const q = selector => root.querySelector(selector);
    const agenda = q('[data-agenda]');
    if (!agenda) return;
    const heading = q('[data-agenda-heading]'), status = q('[data-sync-status]');
    const list = q('[data-event-list]'), legend = q('[data-calendar-list]');
    const refresh = q('[data-refresh-events]');
    const cache = new Map();
    let activeRange = '', payload = null, controller = null, requestNumber = 0, lastSelection = '', debounce;
    let dayTransition = null, calendarSignature = '';
    const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

    function updateScrollEdges(viewport) {
      const scroller = viewport.querySelector('.event-body-scroll');
      viewport.toggleAttribute('data-scroll-top', scroller.scrollTop > 1);
      viewport.toggleAttribute('data-scroll-bottom', scroller.scrollHeight - scroller.clientHeight - scroller.scrollTop > 1);
    }
    const edgeObserver = new ResizeObserver(entries => {
      entries.forEach(entry => {
        const viewport = entry.target.closest('.event-body-viewport');
        if (viewport) updateScrollEdges(viewport);
      });
    });

    function smoothDisclosure(item) {
      let animation = null, bodyAnimation = null, targetOpen = false;
      item.addEventListener('click', event => {
        const summary = item.querySelector('summary');
        if (event.target.closest('summary') !== summary) return;
        event.preventDefault();
        targetOpen = animation ? !targetOpen : !item.open;
        const viewport = item.querySelector('.event-body-viewport');
        const scroller = viewport.querySelector('.event-body-scroll');
        const body = scroller.querySelector('.event-body');
        const startHeight = item.getBoundingClientRect().height;
        const currentStyle = item.open ? getComputedStyle(body) : null;
        const startOpacity = currentStyle?.opacity || '0';
        const startTransform = currentStyle?.transform || 'translateY(8px)';
        animation?.cancel(); bodyAnimation?.cancel();
        item.open = true;
        item.toggleAttribute('data-closing', !targetOpen);
        const closedHeight = summary.getBoundingClientRect().height + 2;
        const endHeight = targetOpen ? list.clientHeight : closedHeight;
        item.style.height = endHeight + 'px';
        updateScrollEdges(viewport);
        if (targetOpen) {
          const bounds = item.getBoundingClientRect(), area = list.getBoundingClientRect();
          const offset = bounds.bottom > area.bottom ? bounds.bottom - area.bottom : bounds.top < area.top ? bounds.top - area.top : 0;
          if (offset) list.scrollBy({top:offset,behavior:reducedMotion.matches ? 'instant' : 'smooth'});
        }
        const finish = () => {
          item.open = targetOpen;
          item.style.removeProperty('height');
          item.removeAttribute('data-closing');
          animation = null; bodyAnimation = null;
          updateScrollEdges(viewport);
        };
        if (reducedMotion.matches || !item.animate) { finish(); return; }
        const timing = {duration:targetOpen ? 360 : 280,easing:'cubic-bezier(.22,1,.36,1)'};
        animation = item.animate([{height:startHeight + 'px'},{height:endHeight + 'px'}],timing);
        bodyAnimation = body.animate([
          {opacity:startOpacity,transform:startTransform},
          {opacity:targetOpen ? 1 : 0,transform:targetOpen ? 'translateY(0)' : 'translateY(6px)'}
        ],timing);
        animation.onfinish = finish;
      });
    }
    let menuAnimation = null, menuTargetOpen = false;
    function setCalendarMenu(open) {
      const panel = legend.querySelector('.calendar-list-items');
      if (!panel) return;
      const style = legend.open ? getComputedStyle(panel) : null;
      const start = {opacity:style?.opacity || '0',transform:style?.transform || 'translateY(-4px)'};
      menuAnimation?.cancel();
      menuTargetOpen = open;
      legend.open = true;
      legend.toggleAttribute('data-closing', !open);
      const finish = () => {
        legend.open = open;
        legend.removeAttribute('data-closing');
        menuAnimation = null;
      };
      if (reducedMotion.matches || !panel.animate) { finish(); return; }
      menuAnimation = panel.animate([start,{opacity:open ? 1 : 0,transform:open ? 'translateY(0)' : 'translateY(-4px)'}],{
        duration:220,easing:'cubic-bezier(.22,1,.36,1)'
      });
      menuAnimation.onfinish = finish;
    }
    legend.addEventListener('click',event => {
      if (!event.target.closest('summary')) return;
      event.preventDefault();
      setCalendarMenu(menuAnimation ? !menuTargetOpen : !legend.open);
    });
    document.addEventListener('pointerdown',event => {
      if (legend.open && !legend.contains(event.target)) setCalendarMenu(false);
    });
    document.addEventListener('keydown',event => {
      if (event.key === 'Escape' && legend.open) {
        event.preventDefault();
        setCalendarMenu(false);
        legend.querySelector('summary')?.focus();
      }
    });

    function state() {
      const buttons = root.querySelectorAll('.day[data-date]');
      return { selected:q('[data-selected-date]').dateTime, start:buttons[0].dataset.date, end:keyFor(nextDay(buttons[buttons.length-1].dataset.date)) };
    }

    function describe(fieldList, label, value) {
      if (!value) return;
      const field = element('div','event-field');
      if (String(value).length > 85) field.classList.add('event-field-wide');
      field.append(element('dt','event-field-name',label),element('dd','event-field-value',value));
      fieldList.append(field);
    }

    function detailsFor(event, calendar, selected) {
      const item = element('details','event-details');
      item.dataset.eventKey = (event.eventIdentifier || event.id) + '|' + event.start;
      const summary = element('summary','event-summary');
      const dot = element('span','event-color'); dot.style.backgroundColor = safeColor(calendar.color); dot.setAttribute('aria-hidden','true');
      const text = element('span','event-summary-text');
      const time = element('span','event-time',eventTime(event,selected));
      const timing = element('span','event-timing'); timing.append(dot,time);
      text.append(timing,element('span','event-title',event.title || 'Без названия'),element('span','event-calendar-name',calendar.title || 'Календарь'));
      summary.append(text,chevron('event-expand'));
      item.append(summary);
      const body = element('div','event-body'), fields = element('dl','event-fields');
      if (event.allDay) {
        const last = parseDay(event.endDay); last.setDate(last.getDate()-1);
        const first = parseDay(event.startDay);
        describe(fields,'Дата',last > first ? fullDayFormat.format(first) + ' — ' + fullDayFormat.format(last) : fullDayFormat.format(first));
      } else {
        describe(fields,'Начало',dateTimeFormat.format(new Date(event.start)));
        describe(fields,'Окончание',dateTimeFormat.format(new Date(event.end)));
      }
      describe(fields,'Календарь',[calendar.title,calendar.source].filter(Boolean).join(' · '));
      describe(fields,'Место',event.location || event.structuredLocation?.title);
      describe(fields,'Часовой пояс',event.timeZone);
      describe(fields,'Организатор',personName(event.organizer));
      if (event.attendees?.length) describe(fields,'Участники',event.attendees.map(person=>{
        const name = personName(person), reply = ({1:'ожидает ответа',2:'принято',3:'отклонено',4:'под вопросом',5:'делегировано',6:'завершено',7:'в процессе'})[person.status];
        return name + (reply ? ' (' + reply + ')' : '');
      }).filter(Boolean).join(', '));
      if (event.recurrence?.length) describe(fields,'Повтор',event.recurrence.map(recurrenceText).join('; '));
      if (event.detached) describe(fields,'Повтор','Изменённый экземпляр повторяющегося события');
      if (event.alarms?.length) describe(fields,'Напоминания',event.alarms.map(alarm => {
        if (alarm.absoluteDate) return dateTimeFormat.format(new Date(alarm.absoluteDate));
        const seconds = Number(alarm.relativeOffset);
        if (!seconds) return 'В момент события';
        let minutes = Math.round(Math.abs(seconds)/60);
        const days = Math.floor(minutes/1440); minutes %= 1440;
        const hours = Math.floor(minutes/60); minutes %= 60;
        const duration = [days && days + ' дн.',hours && hours + ' ч.',minutes && minutes + ' мин.'].filter(Boolean).join(' ');
        return (seconds < 0 ? 'За ' : 'Через ') + (duration || 'меньше минуты');
      }).join('; '));
      describe(fields,'Статус',({1:'Подтверждено',2:'Предварительно',3:'Отменено'})[event.status]);
      describe(fields,'Занятость',({0:'Занят',1:'Свободен',2:'Под вопросом',3:'Недоступен'})[event.availability]);
      if (event.createdAt) describe(fields,'Создано',dateTimeFormat.format(new Date(event.createdAt)));
      if (event.modifiedAt) describe(fields,'Изменено',dateTimeFormat.format(new Date(event.modifiedAt)));
      body.append(fields);
      const url = safeURL(event.url);
      if (url) {
        const link = element('a','event-url',url.href); link.href = url.href; link.target = '_blank'; link.rel = 'noopener noreferrer'; body.append(link);
      }
      if (event.notes) body.append(element('p','event-notes',event.notes));
      const viewport = element('div','event-body-viewport'), scroller = element('div','event-body-scroll');
      scroller.append(body); viewport.append(scroller); item.append(viewport);
      scroller.addEventListener('scroll',() => updateScrollEdges(viewport),{passive:true});
      edgeObserver.observe(scroller); edgeObserver.observe(body);
      smoothDisclosure(item);
      return item;
    }

    function decorateDays() {
      root.querySelectorAll('.day[data-date]').forEach(button => {
        button.querySelector('.event-dots')?.remove();
        if (!payload) return;
        const events = eventsForDay(payload,button.dataset.date);
        if (!events.length) { button.removeAttribute('title'); return; }
        const dots = element('span','event-dots'); dots.setAttribute('aria-hidden','true');
        const calendarIds = [...new Set(events.map(event=>event.calendarId))].slice(0,3);
        calendarIds.forEach(id => { const dot = element('span','event-day-dot'); dot.style.backgroundColor = safeColor(payload.calendars.find(c=>c.id===id)?.color); dots.append(dot); });
        button.append(dots);
        button.title = events.length + ' событий';
      });
    }

    function render() {
      edgeObserver.disconnect();
      const current = state();
      const selectionChanged = lastSelection !== current.selected;
      const previousScroll = list.scrollTop;
      heading.textContent = dayFormat.format(parseDay(current.selected));
      const open = new Set([...list.querySelectorAll('details[open]:not([data-closing])')].map(item=>item.dataset.eventKey));
      list.replaceChildren();
      if (payload) {
        const events = eventsForDay(payload,current.selected);
        q('[data-event-count]').textContent = events.length ? String(events.length) : '';
        if (!events.length) list.append(element('p','agenda-empty','На этот день событий нет'));
        events.forEach(event => {
          const calendar = payload.calendars.find(c=>c.id===event.calendarId) || {};
          const item = detailsFor(event,calendar,current.selected);
          if (open.has(item.dataset.eventKey) && lastSelection === current.selected) item.open = true;
          list.append(item);
        });
        const signature = JSON.stringify(payload.calendars);
        if (calendarSignature !== signature) {
          calendarSignature = signature;
          menuAnimation?.cancel(); menuAnimation = null;
          legend.removeAttribute('data-closing');
          legend.replaceChildren();
          const summary = element('summary','calendar-list-title');
          summary.append(element('span','','Календари · ' + payload.calendars.length),chevron());
          const calendars = element('ul','calendar-list-items');
          payload.calendars.forEach(calendar => {
            const item = element('li','calendar-list-item'), dot = element('span','event-color');
            dot.style.backgroundColor = safeColor(calendar.color); dot.setAttribute('aria-hidden','true');
            item.append(dot,element('span','',calendar.title + (calendar.source ? ' · ' + calendar.source : ''))); calendars.append(item);
          });
          legend.append(summary,calendars);
        }
      } else {
        q('[data-event-count]').textContent = '';
        list.append(element('p','agenda-empty','Подключение к Apple Calendar…'));
        menuAnimation?.cancel(); menuAnimation = null;
        legend.open = false; calendarSignature = '';
        legend.replaceChildren();
      }
      list.scrollTop = selectionChanged ? 0 : previousScroll;
      if (selectionChanged && lastSelection) {
        dayTransition?.cancel();
        if (!reducedMotion.matches && list.animate) {
          dayTransition = list.animate([{opacity:0},{opacity:1}],{
            duration:300,easing:'cubic-bezier(.22,1,.36,1)'
          });
        }
      }
      lastSelection = current.selected;
      decorateDays();
    }

    async function load(force = false) {
      const current = state(), range = current.start + '/' + current.end;
      if (activeRange !== range) {
        activeRange = range; payload = cache.get(range) || null; render();
      }
      if (!force && cache.has(range)) {
        payload = cache.get(range); render();
        if (Date.now() - Date.parse(payload.updatedAt) < 30_000) {
          status.textContent = 'Apple Calendar · обновлено ' + timeFormat.format(new Date(payload.updatedAt));
          refresh.disabled = false;
          return;
        }
      }
      if (!configuration?.token || configuration.baseURL !== 'http://127.0.0.1:8766') {
        status.textContent = 'Apple Calendar не подключён';
        list.replaceChildren(element('p','agenda-empty','Локальный помощник ещё не настроен.')); return;
      }
      controller?.abort(); controller = new AbortController();
      const currentController = controller, number = ++requestNumber;
      const timeout = setTimeout(()=>currentController.abort(),10_000);
      refresh.disabled = true; status.textContent = 'Обновление Apple Calendar…';
      try {
        const response = await fetch(configuration.baseURL + '/v1/events?' + new URLSearchParams({start:current.start,end:current.end}),{
          method:'GET',headers:{Authorization:'Bearer '+configuration.token},signal:currentController.signal,cache:'no-store',credentials:'omit',referrerPolicy:'no-referrer'
        });
        const data = await response.json();
        if (number !== requestNumber) return;
        if (!response.ok) {
          if (data.error === 'calendar_permission') throw new Error('permission');
          throw new Error('service');
        }
        if (data.access !== 'granted' || data.start !== current.start || data.end !== current.end || !Array.isArray(data.events) || !Array.isArray(data.calendars)) throw new Error('service');
        payload = data; cache.set(range,data);
        if (cache.size > 12) cache.delete(cache.keys().next().value);
        render();
        status.textContent = 'Apple Calendar · обновлено ' + timeFormat.format(new Date(data.updatedAt));
      } catch (error) {
        if (number !== requestNumber) return;
        status.textContent = error.message === 'permission' ? 'Нужен доступ к Apple Calendar' : 'Apple Calendar временно недоступен';
        if (!payload) list.replaceChildren(element('p','agenda-empty',error.message === 'permission'
          ? 'Разреши доступ Zen Calendar Bridge в настройках macOS: «Конфиденциальность и безопасность → Календари».'
          : 'Локальный помощник не отвечает. Нажми «Обновить», чтобы повторить подключение.'));
      } finally {
        clearTimeout(timeout);
        if (number === requestNumber) refresh.disabled = false;
      }
    }

    root.addEventListener('zen-calendar-render',()=>{
      const current = state(), range = current.start + '/' + current.end;
      if (range !== activeRange) { requestNumber += 1; controller?.abort(); payload = cache.get(range) || null; }
      render(); clearTimeout(debounce); debounce = setTimeout(()=>load(false),60);
    });
    refresh.addEventListener('click',()=>load(true));
    window.addEventListener('focus',()=>load(true));
    document.addEventListener('visibilitychange',()=>{ if (!document.hidden) load(true); });
    setInterval(()=>{ if (!document.hidden) load(true); },30_000);
    render(); load(true);
  });
  if (window.ZEN_CALENDAR_TESTING) window.ZenCalendarTest = {eventsForDay,eventTime,safeURL,safeColor};
})();
