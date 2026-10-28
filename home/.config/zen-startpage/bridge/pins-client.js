(() => {
  const config = window.ZEN_CALENDAR_BRIDGE;
  const nav = document.querySelector('.bookmarks');
  const reveal = () => document.documentElement.classList.remove('startpage-loading');
  const unavailable = () => {
    if (!nav || nav.childNodes.length) { reveal(); return; }
    const message = document.createElement('p'); message.className = 'bookmarks-empty';
    message.textContent = 'Не удалось загрузить закреплённые вкладки';
    nav.replaceChildren(message); reveal();
  };
  if (!nav || !config?.token || config.baseURL !== 'http://127.0.0.1:8766') { unavailable(); return; }
  const key = value => {
    try { return new URL(value).hostname.replace(/^www\./,''); }
    catch { return ''; }
  };
  const presetRoot = document.querySelector('[data-pin-presets]')?.content || nav;
  const presets = new Map([...presetRoot.querySelectorAll('a.bookmark')].map(link => [key(link.href),link.cloneNode(true)]));
  const arrow = presetRoot.querySelector('.link-arrow')?.cloneNode(true);
  const cacheKey = 'zen-startpage-pins-v1';
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  let signature = '', controller = null, transition = null;
  reducedMotion.addEventListener('change',() => { if (reducedMotion.matches) transition?.cancel(); });
  let notice = null, noticeTimer = null;
  function notify(text) {
    if (!notice) {
      notice = document.createElement('p'); notice.className = 'pin-action-notice';
      notice.setAttribute('role','alert'); document.body.append(notice);
    }
    notice.textContent = text; notice.hidden = false;
    clearTimeout(noticeTimer); noticeTimer = setTimeout(() => { notice.hidden = true; },5000);
  }
  nav.addEventListener('click',async event => {
    if (!event.isTrusted || event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    const link = event.target.closest('a.bookmark');
    if (!link || !nav.contains(link) || !safeURL(link.href)) return;
    event.preventDefault();
    if (link.getAttribute('aria-busy') === 'true') return;
    link.setAttribute('aria-busy','true');
    const request = new AbortController(), timeout = setTimeout(() => request.abort(),2500);
    try {
      const response = await fetch('http://127.0.0.1:8767/v1/activate-pin',{
        method:'POST',headers:{Authorization:'Bearer ' + config.token,'Content-Type':'application/json'},
        body:JSON.stringify({url:link.href}),signal:request.signal,cache:'no-store',credentials:'omit',referrerPolicy:'no-referrer'
      });
      if (!response.ok || !(await response.json()).ok) throw new Error('activation');
    } catch {
      notify('Не удалось переключить закреплённую вкладку. Попробуй ещё раз.');
      update();
    } finally { clearTimeout(timeout); link.removeAttribute('aria-busy'); }
  });

  function safeURL(value) {
    try { const url = new URL(value); return ['http:','https:'].includes(url.protocol) && !url.username && !url.password ? url : null; }
    catch { return null; }
  }
  function safeImage(value) {
    return typeof value === 'string' && value.length <= 512 * 1024
      && /^data:image\/(png|jpeg|gif|webp|avif|x-icon|vnd.microsoft.icon|svg\+xml)[;,]/i.test(value);
  }
  function card(pin) {
    const url = safeURL(pin.url);
    if (!url) return null;
    const preset = presets.get(key(url.href));
    const link = document.createElement('a');
    link.className = 'bookmark'; link.href = url.href;
    link.target = '_blank'; link.rel = 'noopener noreferrer';
    let icon;
    if (pin.customIcon && pin.symbol) {
      icon = document.createElement('span'); icon.className = 'app-icon pin-symbol'; icon.textContent = pin.symbol;
    } else if ((!preset || pin.customIcon) && safeImage(pin.image)) {
      icon = document.createElement('img'); icon.className = 'app-icon'; icon.src = pin.image; icon.alt = '';
    } else if (preset) {
      icon = preset.querySelector('.app-icon')?.cloneNode(true);
    }
    if (!icon) {
      icon = document.createElement('span'); icon.className = 'app-icon pin-monogram';
      icon.textContent = (pin.title || url.hostname.replace(/^www\./,'')).trim().slice(0,1).toUpperCase();
    }
    icon.setAttribute('aria-hidden','true');
    const day = icon.matches('[data-icon-day]') ? icon : icon.querySelector('[data-icon-day]');
    if (day) day.textContent = new Date().getDate();
    const label = document.createElement('span'); label.className = 'app-name';
    label.textContent = preset?.querySelector('.app-name')?.textContent || pin.title || url.host;
    link.setAttribute('aria-label',label.textContent); link.title = label.textContent;
    link.append(icon,label);
    if (arrow) link.append(arrow.cloneNode(true));
    return link;
  }
  function render(data) {
    if (!Array.isArray(data.pins)) return;
    const next = JSON.stringify(data.pins);
    if (next === signature) return;
    const content = document.createDocumentFragment();
    data.pins.forEach(pin => { if (pin && typeof pin === 'object') { const link = card(pin); if (link) content.append(link); } });
    if (!content.childNodes.length) {
      const empty = document.createElement('p'); empty.className = 'bookmarks-empty';
      empty.textContent = 'Закреплённых вкладок пока нет'; content.append(empty);
    }
    const focused = nav.contains(document.activeElement) ? document.activeElement.href : null;
    const firstUpdate = !signature;
    signature = next;
    transition?.cancel();
    nav.replaceChildren(content);
    reveal();
    try { sessionStorage.setItem(cacheKey, next); } catch { /* Storage may be unavailable on file URLs. */ }
    nav.setAttribute('aria-label','Закреплённые вкладки Zen');
    if (focused) [...nav.querySelectorAll('a')].find(a => a.href === focused)?.focus({preventScroll:true});
    if (!firstUpdate && !reducedMotion.matches && nav.animate) {
      transition = nav.animate([{opacity:0},{opacity:1}],{duration:300,easing:'cubic-bezier(.22,1,.36,1)'});
    }
  }
  async function update() {
    controller?.abort(); controller = new AbortController();
    const request = controller;
    const timeout = setTimeout(() => request.abort(),5000);
    try {
      const response = await fetch(config.baseURL + '/v1/pins',{
        headers:{Authorization:'Bearer ' + config.token},signal:request.signal,
        cache:'no-store',credentials:'omit',referrerPolicy:'no-referrer'
      });
      if (!response.ok) throw new Error('pins');
      const data = await response.json();
      if (!Array.isArray(data.pins)) throw new Error('pins');
      if (controller === request) render(data);
    } catch { if (controller === request) unavailable(); }
    finally { clearTimeout(timeout); }
  }
  window.addEventListener('focus',update);
  document.addEventListener('visibilitychange',() => { if (!document.hidden) update(); });
  setInterval(() => { if (!document.hidden) update(); },30000);
  try {
    const cached = JSON.parse(sessionStorage.getItem(cacheKey));
    if (Array.isArray(cached)) render({pins:cached});
  } catch { /* The first load waits for the helper instead of showing sample cards. */ }
  update();
})();
