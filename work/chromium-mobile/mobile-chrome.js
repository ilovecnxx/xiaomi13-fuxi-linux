/* Self-contained Android-Chrome-style mobile chrome for the fuxi Chromium shell.
   Injected into every page (top frame) via CDP Page.addScriptToEvaluateOnNewDocument.
   No Python bridge: navigation uses history/location APIs directly, so it survives even if
   the supervisor dies. Visual language follows Material / Android Chrome: white top bar with
   a rounded address pill, white bottom toolbar (back / forward / home / tabs / menu). */
(function () {
  if (window.top !== window) return;
  if (document.getElementById('fx-bottom')) return;
  if (/^(chrome|devtools|about):/.test(location.protocol)) return;

  var HOME = (window.__FUXI_HOME__ || 'https://www.example.com');
  var C = {
    back: '<svg viewBox="0 0 24 24" width="26" height="26"><path fill="currentColor" d="M15.4 7.4 14 6l-6 6 6 6 1.4-1.4L10.8 12z"/></svg>',
    fwd: '<svg viewBox="0 0 24 24" width="26" height="26"><path fill="currentColor" d="M8.6 16.6 10 18l6-6-6-6-1.4 1.4L13.2 12z"/></svg>',
    home: '<svg viewBox="0 0 24 24" width="26" height="26"><path fill="currentColor" d="M12 3 2 12h3v8h6v-6h2v6h6v-8h3z"/></svg>',
    tabs: '<svg viewBox="0 0 24 24" width="26" height="26"><rect x="3" y="5" width="18" height="14" rx="2" fill="none" stroke="currentColor" stroke-width="2"/><circle cx="8" cy="10" r="1.4" fill="currentColor"/><circle cx="12" cy="10" r="1.4" fill="currentColor"/></svg>',
    menu: '<svg viewBox="0 0 24 24" width="26" height="26"><circle cx="12" cy="5" r="2" fill="currentColor"/><circle cx="12" cy="12" r="2" fill="currentColor"/><circle cx="12" cy="19" r="2" fill="currentColor"/></svg>',
    lock: '<svg viewBox="0 0 24 24" width="15" height="15"><path fill="currentColor" d="M12 2a4 4 0 0 0-4 4v2H6v12h12V8h-2V6a4 4 0 0 0-4-4zm2 6h-4V6a2 2 0 0 1 4 0z"/></svg>',
    reload: '<svg viewBox="0 0 24 24" width="22" height="22"><path fill="currentColor" d="M17.65 6.35A8 8 0 1 0 20 12h-2a6 6 0 1 1-1.76-4.24L13 11h7V4z"/></svg>'
  };

  var css = [
    '#fx-top{position:fixed!important;top:0;left:0;right:0;z-index:2147483646;background:#fff;',
    'box-shadow:0 1px 0 rgba(0,0,0,.14);padding-top:env(safe-area-inset-top);',
    "font-family:system-ui,-apple-system,'Noto Sans CJK SC',sans-serif}",
    '#fx-addr{display:flex;align-items:center;gap:8px;margin:8px 10px;height:46px;background:#f1f3f4;',
    'border-radius:23px;padding:0 14px;color:#202124;font-size:15px}',
    '#fx-addr .fx-lock{color:#5f6368;display:flex}',
    '#fx-url{flex:1;overflow:hidden;white-space:nowrap;text-overflow:ellipsis;outline:none}',
    '#fx-prog{position:absolute;left:0;bottom:0;height:2px;width:0;background:#1a73e8;transition:width .18s}',
    '#fx-bottom{position:fixed!important;bottom:0;left:0;right:0;z-index:2147483646;display:flex;',
    'justify-content:space-around;align-items:stretch;background:#fff;border-top:1px solid #dadce0;',
    'padding-bottom:env(safe-area-inset-bottom);height:calc(54px + env(safe-area-inset-bottom))}',
    '#fx-bottom button{flex:1;border:0;background:transparent;color:#3c4043;display:flex;align-items:center;',
    'justify-content:center;padding:0;touch-action:manipulation;-webkit-tap-highlight-color:transparent}',
    '#fx-bottom button:active{background:#e8eaed}',
    '#fx-bottom button.fx-dis{opacity:.32}',
    '#fx-sheet{position:fixed;inset:0;z-index:2147483647;background:rgba(0,0,0,.35);display:none;align-items:flex-end}',
    '#fx-sheet.on{display:flex}',
    '#fx-sheet .in{width:100%;background:#fff;border-radius:18px 18px 0 0;padding:6px 0 20px;',
    "font-family:system-ui,sans-serif;box-shadow:0 -2px 16px rgba(0,0,0,.2)}",
    '#fx-sheet .r{display:flex;align-items:center;gap:16px;padding:15px 22px;font-size:16px;color:#202124}',
    '#fx-sheet .r:active{background:#f1f3f4}',
    '#fx-sheet .h{font-size:12px;letter-spacing:.06em;color:#5f6368;padding:12px 22px 4px;text-transform:uppercase}'
  ].join('');

  function mk(t, a) { var e = document.createElement(t); if (a) for (var k in a) e.setAttribute(k, a[k]); return e; }
  function normUrl(v) {
    v = (v || '').trim();
    if (!v) return HOME;
    if (/^[a-z]+:\/\//i.test(v)) return v;
    if (/^[\w-]+(\.[\w-]+)+(\/.*)?$/.test(v)) return 'https://' + v;
    return 'https://www.google.com/search?q=' + encodeURIComponent(v);
  }

  function historyCanBack() {
    try { return (parseInt(sessionStorage.getItem('fx_h') || '0', 10)) > 0; } catch (e) { return history.length > 1; }
  }
  function bumpHistory(d) {
    // track depth ourselves because history.length grows monotonically on SPA too
    try {
      var n = parseInt(sessionStorage.getItem('fx_h') || '0', 10) + d;
      if (n < 0) n = 0;
      sessionStorage.setItem('fx_h', String(n));
      return n;
    } catch (e) { return d; }
  }

  var BACK = 0;   // tracked depth
  try { BACK = parseInt(sessionStorage.getItem('fx_h') || '0', 10); } catch (e) {}

  function build() {
    var st = mk('style'); st.textContent = css; document.documentElement.appendChild(st);

    var top = mk('div', { id: 'fx-top' });
    var addr = mk('div', { id: 'fx-addr' });
    var lock = mk('span', { 'class': 'fx-lock' }); lock.innerHTML = C.lock;
    var url = mk('div', { id: 'fx-url', contenteditable: 'true', spellcheck: 'false', inputmode: 'url', enterkeyhint: 'go' });
    addr.appendChild(lock); addr.appendChild(url); top.appendChild(addr);
    var prog = mk('div', { id: 'fx-prog' }); top.appendChild(prog);
    document.documentElement.appendChild(top);

    var bottom = mk('div', { id: 'fx-bottom' });
    function mkbtn(a, icon) { var b = mk('button', { 'data-a': a }); b.innerHTML = icon; bottom.appendChild(b); return b; }
    var bBack = mkbtn('back', C.back), bFwd = mkbtn('fwd', C.fwd), bHome = mkbtn('home', C.home),
        bTabs = mkbtn('tabs', C.tabs), bMenu = mkbtn('menu', C.menu);
    bottom.addEventListener('click', function (ev) {
      var t = ev.target.closest('button'); if (!t) return; ev.preventDefault(); act(t.getAttribute('data-a'));
    });
    document.documentElement.appendChild(bottom);

    var sheet = mk('div', { id: 'fx-sheet' }); sheet.onclick = function (e) { if (e.target === sheet) sheet.classList.remove('on'); };
    document.documentElement.appendChild(sheet);

    window.__fx = { url: url, prog: prog, bBack: bBack, bFwd: bFwd, sheet: sheet };

    url.addEventListener('focus', function () { url.textContent = location.href; var r = document.createRange(); r.selectNodeContents(url); var s = getSelection(); s.removeAllRanges(); s.addRange(r); });
    url.addEventListener('keydown', function (e) { if (e.key === 'Enter') { e.preventDefault(); location.href = normUrl(url.textContent); url.blur(); } });
    url.addEventListener('blur', function () { renderUrl(); });

    bHome.addEventListener('click', function () { /* handled by act */ });

    renderUrl(); renderNav();
    document.addEventListener('click', function () { setTimeout(renderNav, 50); }, true);
    window.addEventListener('popstate', function () { renderNav(); renderUrl(); });
    setInterval(function () { renderUrl(); renderNav(); }, 1200);
  }

  function renderUrl() {
    if (!window.__fx) return; var u = window.__fx.url;
    if (document.activeElement === u) return;
    var t = location.href;
    try { var p = new URL(location.href); t = p.host + (p.pathname === '/' ? '' : p.pathname); } catch (e) {}
    u.textContent = t || location.href;
  }
  function renderNav() {
    if (!window.__fx) return;
    var canBack = historyCanBack();
    window.__fx.bBack.classList.toggle('fx-dis', !canBack);
  }
  function prog(v, on) {
    if (!window.__fx) return;
    window.__fx.prog.style.width = on ? (v || 20) + '%' : '100%';
    if (!on) setTimeout(function () { if (window.__fx) window.__fx.prog.style.width = '0'; }, 250);
  }

  function act(a) {
    if (a === 'back') { bumpHistory(-1); history.back(); setTimeout(renderNav, 300); }
    else if (a === 'fwd') { bumpHistory(1); history.forward(); setTimeout(renderNav, 300); }
    else if (a === 'home') { location.href = HOME; }
    else if (a === 'tabs') { openSheet('tabs'); }
    else if (a === 'menu') { openSheet('menu'); }
  }

  function openSheet(mode) {
    var s = window.__fx.sheet; s.classList.add('on'); s.innerHTML = '';
    var inner = mk('div', { 'class': 'in' });
    function head(t) { var h = mk('div', { 'class': 'h' }); h.textContent = t; inner.appendChild(h); }
    function row(t, fn) { var r = mk('div', { 'class': 'r' }); r.textContent = t; r.onclick = function () { s.classList.remove('on'); fn(); }; inner.appendChild(r); }
    if (mode === 'tabs') {
      head('标签页');
      row('当前标签 · ' + (document.title || location.host), function () {});
      row('＋ 新标签页', function () { window.open(HOME, '_blank'); });
      row('关闭标签', function () { location.href = 'about:blank'; });
    } else {
      head('菜单');
      row('新标签页', function () { window.open(HOME, '_blank'); });
      row('刷新', function () { location.reload(); });
      row('回到主页', function () { location.href = HOME; });
      row('复制当前网址', function () { try { navigator.clipboard.writeText(location.href); } catch (e) {} });
      row('查找…', function () { window.find && window.find(''); });
      row('关闭菜单', function () {});
    }
    s.appendChild(inner);
  }

  // loading progress via Navigation events + timers
  window.addEventListener('beforeunload', function () { prog(20, true); });
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', build);
  else build();
})();
