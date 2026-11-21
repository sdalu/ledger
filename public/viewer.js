
(() => {
  let here = document.body.dataset.stamp;
  // the page as the server sent it, before anything below opens a fold or
  // wakes a button: what a change made elsewhere is compared with
  const sentMain = document.querySelector('main')?.cloneNode(true);
  // the side list and the goal's words are folds on a narrow page and open
  // while the page is wide; narrow, each keeps its own state
  const wide = matchMedia('(min-width: 64rem)');
  const widthFolds = [...document.querySelectorAll('details.sections, .ledger-main > .goal > .goal-words')];
  // a fold with an id keeps its state for the tab: on load, and in a part
  // drawn again after a change
  const foldsIn = root => {
    for (const d of [...(root.matches?.('details[id]') ? [root] : []), ...root.querySelectorAll('details[id]')]) {
      try {
        const v = sessionStorage.getItem('open:' + d.id);
        if (v !== null) d.open = v === '1';
      } catch (e) {}
      d.addEventListener('toggle', () => {
        if (widthFolds.includes(d) && wide.matches) return;
        try { sessionStorage.setItem('open:' + d.id, d.open ? '1' : '0'); } catch (e) {}
      });
    }
  };
  foldsIn(document);
  const narrowState = new Map(widthFolds.map(d => [d, d.open]));
  for (const d of widthFolds) {
    d.addEventListener('toggle', () => { if (!wide.matches) narrowState.set(d, d.open); });
  }
  const fitFolds = () => { for (const d of widthFolds) d.open = wide.matches || narrowState.get(d); };
  fitFolds();
  wide.addEventListener('change', fitFolds);
  // the text last selected outside a form, for the quote buttons: a click
  // on the button empties the selection, so it is kept as it is made; the
  // buttons stay disabled until there is something to quote
  let quote = '';
  document.addEventListener('selectionchange', () => {
    const s = document.getSelection();
    const t = s ? s.toString().trim() : '';
    if (!t) return;
    const n = s.anchorNode && (s.anchorNode.nodeType === 1 ? s.anchorNode : s.anchorNode.parentElement);
    if (n && n.closest('form')) return;
    quote = t;
    for (const b of document.querySelectorAll('button.a-quote')) b.disabled = false;
  });
  // the controls that need script, woken in a root: the whole page on load,
  // a card swapped in after a send
  const wire = root => {
    for (const b of root.querySelectorAll('button.a-quote')) {
      b.hidden = false;
      b.disabled = !quote;
      b.addEventListener('click', () => {
        if (!quote) return;
        const ta = b.form.querySelector('textarea[name="text"]');
        const fold = ta.closest('details');
        if (fold) fold.open = true;
        const q = quote.split('\n').map(l => '> ' + l).join('\n');
        // a blank line after the quote: a comment typed straight below a
        // quoted line would read as part of the quote
        ta.value = (ta.value.trim() ? ta.value.replace(/\s*$/, '\n\n') : '') + q + '\n\n';
        ta.focus();
        ta.setSelectionRange(ta.value.length, ta.value.length);
      });
    }
    // a choice that asks for a comment opens its fold and requires the text
    // while it is picked
    for (const radio of root.querySelectorAll('form.say input[type="radio"][name="choice"]')) {
      const form = radio.form;
      const sync = () => {
        for (const c of form.querySelectorAll('.choice')) {
          const need = c.querySelector('.comment-needed');
          if (!need) continue;
          const picked = c.querySelector('input[type="radio"]').checked;
          const ta = c.querySelector('textarea');
          ta.required = picked;
          if (picked) c.querySelector('details').open = true;
        }
      };
      radio.addEventListener('change', sync);
      sync();
    }
    // Cancel on a request closes its fold and gives the focus back to the
    // trash that opened it; without script the trash closes it as well
    for (const b of root.querySelectorAll('button.a-cancel')) {
      b.hidden = false;
      b.addEventListener('click', () => {
        const fold = b.closest('details');
        fold.open = false;
        fold.querySelector('summary').focus();
      });
    }
    for (const b of root.querySelectorAll('button.a-expand')) {
      b.hidden = false;
      b.addEventListener('click', () => expand(b));
    }
  };
  wire(document);
  // what was chosen or typed and not sent survives the Refresh of the
  // "Ledger changed" note: kept per ledger and item in sessionStorage, put
  // back on load with a line saying so; a choice no longer offered is said,
  // not dropped silently; a send clears it; without storage nothing is kept
  const lid = (location.pathname.match(/^\/l\/([^/]+)/) || [])[1] || '';
  // the answer forms in a root, each under its item's ref (#2 for a second
  // form of the same item)
  const formsIn = root => {
    const seen = {};
    const out = [];
    for (const f of root.querySelectorAll('form.say')) {
      const ref = f.elements.ref && f.elements.ref.value;
      if (!ref || f.closest('.drop-fold')) continue;
      seen[ref] = (seen[ref] || 0) + 1;
      out.push([f, ref + (seen[ref] > 1 ? '#' + seen[ref] : '')]);
    }
    return out;
  };
  const draftForms = () => formsIn(document).map(([f, ref]) => [f, 'draft:' + lid + ':' + ref]);
  // what a form holds that the server did not send, or null
  const draftOf = f => {
    const radios = {}, texts = {};
    for (const r of f.querySelectorAll('input[type="radio"]')) {
      if (r.checked && r.checked !== r.defaultChecked) radios[r.name] = r.value;
    }
    for (const t of f.querySelectorAll('textarea, input[type="text"]')) {
      if (t.value !== t.defaultValue) texts[t.name] = t.value;
    }
    return Object.keys(radios).length || Object.keys(texts).length ? {radios, texts} : null;
  };
  const keepDrafts = () => {
    for (const [f, key] of draftForms()) {
      const d = draftOf(f);
      try {
        if (d) sessionStorage.setItem(key, JSON.stringify(d));
        else sessionStorage.removeItem(key);
      } catch (e) {}
    }
  };
  const letterOf = v => v.split(' = ')[0].replace(/^(pick|note):/, '');
  // a draft put back into a form drawn anew, with a line saying what came
  // back and what is no longer offered; `since` names what came between
  const putBack = (f, d, since) => {
    const kept = [], gone = [];
    for (const [name, value] of Object.entries(d.radios || {})) {
      const r = [...f.querySelectorAll('input[type="radio"]')].find(x => x.name === name && x.value === value);
      if (r) {
        r.checked = true;
        r.dispatchEvent(new Event('change', {bubbles: true}));
        kept.push('your choice ' + letterOf(value));
      } else gone.push('Your choice ' + letterOf(value));
    }
    let typed = 0;
    for (const [name, value] of Object.entries(d.texts || {})) {
      const t = [...f.querySelectorAll('textarea, input[type="text"]')].find(x => x.name === name);
      if (t) {
        t.value = value;
        const fold = t.closest('details');
        if (fold) fold.open = true;
        typed++;
      } else gone.push('Your comment on ' + letterOf(name));
    }
    if (typed) kept.push(typed > 1 ? 'your comments' : 'your comment');
    const lines = [];
    if (kept.length) lines.push('Kept from before the ' + since + ': ' + kept.join(' and ') + ', not sent yet.');
    for (const g of gone) lines.push(g + ' is no longer offered; nothing was sent.');
    if (!lines.length) return;
    const p = document.createElement('p');
    p.className = 'draft-note';
    p.setAttribute('role', 'status');
    p.textContent = lines.join(' ');
    f.prepend(p);
  };
  // a send clears the draft its form kept
  const clearOnSend = root => {
    for (const [f, ref] of formsIn(root)) {
      const key = 'draft:' + lid + ':' + ref;
      f.addEventListener('submit', () => { try { sessionStorage.removeItem(key); } catch (e) {} });
    }
  };
  clearOnSend(document);
  for (const [f, key] of draftForms()) {
    let d = null;
    try {
      d = JSON.parse(sessionStorage.getItem(key) || 'null');
      sessionStorage.removeItem(key);
    } catch (e) { d = null; }
    if (d) putBack(f, d, 'refresh');
  }
  // a mockup opens beside the page when there is room for both, over it
  // when there is not; the frame keeps the card's sandbox; closing gives
  // the focus back to the button that opened it
  let pane = null, dlg = null, opener = null;
  const shell = (tag, cls, id) => {
    const box = document.createElement(tag);
    box.className = cls;
    box.innerHTML = '<header><span class="pane-title" id="' + id + '"></span><span class="pane-actions">'
      + '<button type="button" class="a-full" hidden>__ICON_MAXIMIZE__<span>Full screen</span></button>'
      + '<button type="button" class="a-close">__ICON_X__Close</button></span></header><div class="pane-view"></div>';
    box.setAttribute('aria-labelledby', id);
    // full screen where the browser allows it: the same pane over the
    // whole screen; Esc or the same button leaves it
    const full = box.querySelector('.a-full');
    if (document.fullscreenEnabled) {
      full.hidden = false;
      // the label follows the state once the change settles; the event
      // alone can come after the call resolves
      const label = () => {
        full.querySelector('span').textContent =
          document.fullscreenElement === box ? 'Exit full screen' : 'Full screen';
      };
      full.addEventListener('click', () => {
        const change = document.fullscreenElement === box
          ? document.exitFullscreen() : box.requestFullscreen();
        change.then(label, label);
      });
      document.addEventListener('fullscreenchange', label);
    }
    document.body.append(box);
    return box;
  };
  const fill = (box, b) => {
    box.querySelector('.pane-title').textContent = b.dataset.label;
    const view = box.querySelector('.pane-view');
    view.replaceChildren();
    let el;
    if (b.dataset.kind === 'image') {
      el = document.createElement('img');
      el.alt = 'mockup ' + b.dataset.label;
      el.src = b.dataset.src;
    } else if (b.dataset.kind === 'text') {
      const fig = b.closest('figure');
      el = (fig.querySelector('pre.figure-full') || fig.querySelector('pre')).cloneNode(true);
      el.hidden = false;
    } else {
      el = document.createElement('iframe');
      el.setAttribute('sandbox', 'allow-scripts');
      el.title = 'mockup ' + b.dataset.label;
      el.src = b.dataset.src;
    }
    view.append(el);
  };
  const paneOpen = () => pane && !pane.hidden;
  const closePane = (refocus = true) => {
    if (!paneOpen()) return;
    if (document.fullscreenElement === pane) document.exitFullscreen();
    pane.hidden = true;
    document.body.classList.remove('is-paned');
    if (refocus && opener) opener.focus();
  };
  const expand = b => {
    opener = b;
    if (wide.matches) {
      if (!pane) {
        pane = shell('aside', 'mock-pane', 'mock-pane-title');
        pane.querySelector('.a-close').addEventListener('click', () => closePane());
      }
      fill(pane, b);
      pane.hidden = false;
      document.body.classList.add('is-paned');
      pane.querySelector('.a-close').focus();
    } else {
      if (!dlg) {
        dlg = shell('dialog', 'mock-dialog', 'mock-dialog-title');
        dlg.querySelector('.a-close').addEventListener('click', () => dlg.close());
        dlg.addEventListener('close', () => { if (opener) opener.focus(); });
      }
      fill(dlg, b);
      dlg.showModal();
    }
  };
  document.addEventListener('keydown', e => { if (e.key === 'Escape') closePane(); });
  // an open status tag is one pill: a click on its explanation closes it
  // too, not only a click on the word (the summary toggles by itself)
  document.addEventListener('click', e => {
    const fold = e.target.closest('details.status-fold[open]');
    if (fold && !e.target.closest('summary')) fold.open = false;
  });
  // a window narrowed below the pane's width moves the mockup over the page
  // a link to the note box opens its fold and puts the cursor in it
  const toNote = () => {
    const box = document.getElementById('say-note');
    if (!box) return;
    box.closest('details').open = true;
    box.focus();
  };
  // delegated: the head is swapped after a send
  document.addEventListener('click', e => {
    if (!e.target.closest('a[href="#say-note"]')) return;
    e.preventDefault();
    toNote();
  });
  if (location.hash === '#say-note') toNote();
  // a link to a card or a criterion inside a closed fold (On record) opens
  // every fold around it, then shows it
  const reveal = () => {
    const id = decodeURIComponent(location.hash.slice(1));
    const el = id && id !== 'say-note' && document.getElementById(id);
    if (!el) return;
    for (let f = el.closest('details'); f; f = f.parentElement.closest('details')) f.open = true;
    el.scrollIntoView({block: 'start'});
  };
  window.addEventListener('hashchange', reveal);
  reveal();
  wide.addEventListener('change', e => {
    if (!e.matches && paneOpen()) { closePane(false); expand(opener); }
  });
  // a reload would throw away what the user has typed or chosen, or the
  // mockup open beside it: a form differing from what the server sent, a
  // box being typed in, or a pane or window open holds it, and a note says
  // the ledger changed; checked again once the answer comes back
  const dirty = () => [...document.querySelectorAll('form.say textarea, form.say input[type="text"]')]
      .some(t => t.value !== t.defaultValue || t === document.activeElement)
    || [...document.querySelectorAll('form.say input[type="radio"]')].some(r => r.checked !== r.defaultChecked)
    || paneOpen() || (dlg && dlg.open);
  let note = null;
  const stale = () => {
    if (note) return;
    note = document.createElement('div');
    note.className = 'stale-note';
    note.setAttribute('role', 'status');
    note.innerHTML = '<span>Ledger changed</span> <button type="button" class="a-refresh">__ICON_REFRESH__Refresh</button>';
    note.querySelector('.a-refresh').addEventListener('click', () => {
      keepDrafts();
      try { sessionStorage.setItem('scroll:' + location.pathname, String(scrollY)); } catch (e) {}
      location.reload();
    });
    document.body.append(note);
  };
  // a changed ledger is pushed over /events; the poll stays as the fallback,
  // every 3 s while the stream is not open and every 30 s while it is
  const ledgerPage = document.body.dataset.page === 'ledger';
  // after the note's Refresh, the reader's place comes back; a hash in the
  // address names a place of its own and wins
  try {
    const y = sessionStorage.getItem('scroll:' + location.pathname);
    if (y !== null) {
      sessionStorage.removeItem('scroll:' + location.pathname);
      if (!location.hash) scrollTo(0, Number(y));
    }
  } catch (e) {}
  // a send in flight, or its own stamp not yet taken as the page's: the
  // user's own send is not a change to announce
  let sending = false;
  // what a page cannot draw again in place: a ledger page says so and
  // waits; the index is a queue to glance at and reloads quietly unless a
  // draft or pane holds it
  const fallback = () => { if (ledgerPage || dirty()) stale(); else location.reload(); };
  // the parts of a page drawn again one at a time when the ledger changes
  // elsewhere, each under a key naming it in the page shown and the page
  // fetched; the rest of the page must be as the server last sent it
  const PARTS = {
    ledger: [['header.ledger-head', () => 'head'], ['nav.question-nav', () => 'nav'],
             ['h2[id] > .count', e => 'count:' + e.parentElement.id], ['section.waiting form.give-all', () => 'give-all'],
             ['[data-key]', e => e.dataset.key], ['details.done-fold[id]', e => e.id], ['li[id]', e => e.id]],
    index: [['p.queue-summary', () => 'summary'], ['[data-key]', e => e.dataset.key]],
  }[document.body.dataset.page];
  const keyOf = el => { const p = PARTS.find(([sel]) => el.matches(sel)); return p ? p[1](el) : ''; };
  // key => element, in the page's order; a part inside another goes with
  // it (a card of a record fold is drawn with the fold)
  const partsOf = root => {
    const out = new Map(), taken = new Set();
    for (const el of PARTS ? root.querySelectorAll(PARTS.map(([sel]) => sel).join(', ')) : []) {
      let inner = false;
      for (let up = el.parentElement; up && up !== root && !inner; up = up.parentElement) inner = taken.has(up);
      if (inner) continue;
      taken.add(el);
      out.set(keyOf(el), el);
    }
    return out;
  };
  // the tips are numbered across the page: a part's own markup does not
  // change when a part above it gains or loses one
  const norm = html => html.replace(/tip-\d+/g, 'tip-#');
  // the page without its parts: what a part's coming, going or moving
  // leaves alone
  const skeleton = main => {
    const copy = main.cloneNode(true);
    for (const el of partsOf(copy).values()) el.remove();
    return norm(copy.innerHTML);
  };
  const snapshot = main => ({
    parts: new Map([...partsOf(main)].map(([k, el]) => [k, norm(el.outerHTML)])),
    skel: skeleton(main),
  });
  // what the server last sent for each part, never the live page, which
  // wire() and the user change
  let last = PARTS && sentMain ? snapshot(sentMain) : null;
  // a part the user holds: a form differing from what the server sent, a
  // focused element, its picture open, or a tray item for it
  const holds = el => el.contains(document.activeElement)
    || [...el.querySelectorAll('form textarea, form input[type="text"]')].some(t => t.value !== t.defaultValue)
    || [...el.querySelectorAll('form input[type="radio"], form input[type="checkbox"]')].some(r => r.checked !== r.defaultChecked)
    || (!!opener && el.contains(opener) && (paneOpen() || !!(dlg && dlg.open)))
    || tray.some(i => i.card === el.id || !!el.querySelector('[id="' + CSS.escape(i.card) + '"]'));
  const foldsOf = root => [...(root.matches('details[id]') ? [root] : []), ...root.querySelectorAll('details[id]')];
  // a part drawn anew in place of `old`: the folds the user opened or
  // closed stay so, a collapsed receipt stays collapsed, and what the
  // script added to the head moves into the new one
  const swapPart = (old, fresh) => {
    const mine = document.importNode(fresh, true);
    foldsIn(mine);
    const open = new Map(foldsOf(old).map(d => [d.id, d.open]));
    for (const d of foldsOf(mine)) if (open.has(d.id)) d.open = open.get(d.id);
    if (old.classList.contains('is-collapsed') && mine.querySelector('.sent, .sent-line')) mine.classList.add('is-collapsed');
    const sw = old.querySelector(':scope > .batch-switch');
    if (sw) {
      const at = mine.querySelector(':scope > .waker') || mine.querySelector(':scope > nav.tiles');
      if (at) at.before(sw); else mine.append(sw);
    }
    const ls = old.querySelector('.live-state');
    if (ls) (mine.matches('.receipt, .queue-summary') ? mine : mine.querySelector('.receipt') || mine).append(' ', ls);
    old.replaceWith(mine);
    wire(mine);
    clearOnSend(mine);
    return mine;
  };
  // parts held while the page changed: key => the part as the server now
  // has it (null when it is gone), and the line that says so
  const pending = new Map(), flags = new Map();
  const flag = (key, el, fresh) => {
    pending.set(key, fresh);
    if (flags.get(key)?.isConnected) return;
    const line = document.createElement(el.matches('tr') ? 'div' : 'p');
    line.className = 'changed-line';
    line.setAttribute('role', 'status');
    const what = document.createElement('span');
    what.textContent = 'Changed since you started';
    const b = button('a-take', 'Update');
    b.addEventListener('click', () => take(key));
    line.append(what, ' ', b);
    const head = el.querySelector(':scope > .card-head, :scope > summary');
    if (head) head.after(line);
    else (el.matches('tr') ? el.cells[0] : el).prepend(line);
    flags.set(key, line);
  };
  const unflag = key => { flags.get(key)?.remove(); flags.delete(key); pending.delete(key); };
  // Update on a held part: it is drawn as the server now has it, and what
  // was typed or chosen in it comes back where its field still is
  const take = key => {
    const old = partsOf(document.querySelector('main')).get(key);
    const fresh = pending.get(key);
    unflag(key);
    if (!old) return;
    const drafts = formsIn(old).map(([f, ref]) => [ref, draftOf(f)]).filter(([, d]) => d);
    settle(() => {
      if (!fresh) { old.remove(); last.parts.delete(key); return; }
      const mine = swapPart(old, fresh);
      const byRef = new Map(formsIn(mine).map(([f, ref]) => [ref, f]));
      for (const [ref, d] of drafts) if (byRef.has(ref)) putBack(byRef.get(ref), d, 'update');
      last.parts.set(key, norm(fresh.outerHTML));
      markTray();
      drawBar();
      mine.tabIndex = -1;
      mine.focus({preventScroll: true});
    });
  };
  // the live counterpart of an element of the fetched page outside the
  // parts: by its id, its part, or its place beside one
  const locate = (el, mainNew, keys, now) => {
    if (el === mainNew) return document.querySelector('main');
    if (keys.has(el)) return now.get(keys.get(el)) || null;
    if (el.id) return document.getElementById(el.id);
    const prev = el.previousElementSibling;
    const at = prev ? locate(prev, mainNew, keys, now)?.nextElementSibling
      : locate(el.parentElement, mainNew, keys, now)?.firstElementChild;
    return at && at.tagName === el.tagName ? at : null;
  };
  // the parts of the page shown that the fetched one no longer has go,
  // unless held
  const drop = (parts, now) => {
    for (const [k, el] of now) {
      if (parts.has(k)) continue;
      if (holds(el)) { flag(k, el, null); continue; }
      el.remove();
      now.delete(k);
      last.parts.delete(k);
      unflag(k);
    }
  };
  // the fetched page drawn into this one, part by part; false when it
  // cannot be (the rest of the page differs, or a part has no place)
  const apply = doc => {
    const mainNew = doc.querySelector('main');
    const fresh = snapshot(mainNew);
    if (fresh.skel !== last.skel) return false;
    const parts = partsOf(mainNew);
    const keys = new Map([...parts].map(([k, el]) => [el, k]));
    const now = partsOf(document.querySelector('main'));
    drop(parts, now);
    for (const [k, el] of parts) {
      let mine = now.get(k);
      const html = fresh.parts.get(k);
      if (mine && last.parts.get(k) !== html) {
        if (holds(mine)) { flag(k, mine, el); continue; }
        unflag(k);
        mine = swapPart(mine, el);
        now.set(k, mine);
      } else if (mine && pending.has(k)) unflag(k);
      const prev = el.previousElementSibling;
      const at = locate(prev || el.parentElement, mainNew, keys, now);
      if (!at) return false;
      if (!mine) {
        mine = document.importNode(el, true);
        foldsIn(mine);
        if (prev) at.after(mine); else at.prepend(mine);
        wire(mine);
        clearOnSend(mine);
        now.set(k, mine);
      } else if (prev ? at.nextElementSibling !== mine : at.firstElementChild !== mine) {
        if (prev) at.after(mine); else at.prepend(mine);
      }
      last.parts.set(k, html);
    }
    document.title = doc.title;
    if (ledgerPage) { markTray(); drawBar(); }
    return true;
  };
  // the element at the top of the window, so that the page does not move
  // under the reader when a part above it is drawn anew
  const anchor = () => {
    for (const el of document.querySelectorAll('main h2, main [id], main [data-key]')) {
      const r = el.getBoundingClientRect();
      if (r.bottom > 0 && r.height > 0) return [el, r.top];
    }
    return null;
  };
  let swapping = false, again = false;
  const fetchPage = async () => {
    try {
      const r = await fetch(location.pathname, {cache: 'no-store', credentials: 'same-origin'});
      if (r.status !== 200) return null;
      const doc = new DOMParser().parseFromString(await r.text(), 'text/html');
      // a page of another kind (a sign-in page after the session ended)
      // has no parts to take
      const same = doc.body.dataset.page === document.body.dataset.page && doc.querySelector('main') && doc.body.dataset.stamp;
      return same ? doc : null;
    } catch (e) { return null; }
  };
  // a change made elsewhere: the page is fetched again and only the parts
  // the server now draws differently are drawn anew
  const outside = async () => {
    if (swapping) { again = true; return; }
    swapping = true;
    const doc = await fetchPage();
    // the user's own send draws the page from its own answer
    if (sending) { swapping = false; return; }
    let ok = !!doc;
    const stamp = doc && doc.body.dataset.stamp;
    if (ok && stamp !== here) {
      const active = document.activeElement;
      await settle(() => {
        const a = anchor();
        ok = apply(doc);
        const top = a && a[0].isConnected ? a[0].getBoundingClientRect().top : null;
        if (top !== null && top !== a[1]) scrollBy(0, top - a[1]);
        if (active && active.isConnected && document.activeElement !== active) active.focus({preventScroll: true});
      });
      if (ok) {
        here = stamp;
        document.body.dataset.stamp = stamp;
        known = waitingSig(doc);
      }
    }
    swapping = false;
    if (!ok) { again = false; fallback(); return; }
    if (again) { again = false; outside(); }
  };
  const changed = stamp => {
    if (sending || stamp.trim() === here) return;
    if (last) outside(); else fallback();
  };
  // after the user's own send, the parts it drew again are as the server
  // sent them, and so is the rest of the page
  const rebase = (doc, keys) => {
    const mainNew = last && doc.querySelector('main');
    if (!mainNew) return;
    const parts = partsOf(mainNew);
    last.skel = skeleton(mainNew);
    for (const k of keys) {
      if (parts.has(k)) last.parts.set(k, norm(parts.get(k).outerHTML)); else last.parts.delete(k);
    }
  };
  // an answer or a word is sent with fetch: the answered card is swapped for
  // its receipt, collapsed to one line, and the page moves on to the next card
  // waiting, which is focused and pulses once. Anything else, a refusal, a
  // failed fetch or a card that did not become a receipt, goes the plain way
  // the form would have gone
  const reduced = () => matchMedia('(prefers-reduced-motion: reduce)').matches;
  // the regions that say what waits on the user, drawn again from the page a
  // send came back with, so the page agrees with itself
  const regions = ['.ledger-head p.next', '.ledger-head nav.tiles', '.ledger-details .status',
                   'section.waiting > h2 .count', 'nav.question-nav'];
  const giveAll = 'section.waiting form.give-all';
  // the parts (PARTS) those regions are whole of: the head is drawn again
  // only in part, so it is not among them
  const redrawn = ['nav', 'count:waiting', 'give-all'];
  // the waiting cards as the server last showed them: id, title and question
  const waitingSig = root => new Map([...root.querySelectorAll('section.waiting > ul.entries:not(.answered) > li[id]')]
    .map(li => [li.id, [li.querySelector('.card-head .text')?.textContent, li.querySelector(':scope > .detail')?.textContent].join('|')]));
  let known = waitingSig(document);
  const redraw = doc => {
    for (const sel of regions) {
      const a = document.querySelector(sel), b = doc.querySelector(sel);
      if (!a || !b) continue;
      if (sel.endsWith('.count')) a.textContent = b.textContent;
      else { const c = document.importNode(b, true); a.replaceWith(c); wire(c); }
    }
    // the one-click bar for several pieces comes and goes with what still
    // waits: a word sent on one card leaves it naming pieces already given
    const bar = document.querySelector(giveAll), fresh = doc.querySelector(giveAll);
    if (bar && !fresh) bar.remove();
    else if (bar && fresh) bar.replaceWith(document.importNode(fresh, true));
  };
  // anything but the cards acted on gone from what waits, or changed, is
  // somebody else's change
  const outsideOf = (doc, mine) => {
    const now = waitingSig(doc);
    return [now, [...known].some(([id, sig]) => !mine.includes(id) && now.get(id) !== sig)
      || [...now.keys()].some(id => !known.has(id))];
  };
  const settle = fn => {
    if (reduced() || !document.startViewTransition) { fn(); return Promise.resolve(); }
    return document.startViewTransition(fn).finished.catch(() => {});
  };
  document.addEventListener('submit', async e => {
    const f = e.target;
    if (!f.matches || !f.matches('form.say') || f.dataset.plain) return;
    if (batch && /\/say$/.test(new URL(f.action).pathname)) {
      const kind = trayKind(f, e.submitter);
      if (kind) { e.preventDefault(); toTray(f, e.submitter, kind); return; }
    }
    const card = f.closest('li.is-card[id]');
    if (!card || !/^[qp]-/.test(card.id) || !/\/say$/.test(new URL(f.action).pathname)) return;
    e.preventDefault();
    if (sending) return;
    sending = true;
    const plain = () => {
      sending = false;
      f.dataset.plain = '1';
      f.requestSubmit(e.submitter);
    };
    let doc = null, r = null;
    try {
      r = await fetch(f.action, {
        method: 'POST',
        credentials: 'same-origin',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: new URLSearchParams(new FormData(f, e.submitter)),
      });
      if (r.ok && r.redirected) doc = new DOMParser().parseFromString(await r.text(), 'text/html');
    } catch (err) { doc = null; }
    if (!doc) return plain();
    // a question asked about a card, or a picture asked of it, leaves it
    // answerable: only that part is drawn again, so an answer being
    // written on the card stays
    const ask = f.closest('.ask-about, .picture-ask');
    if (ask) {
      const which = ask.matches('.ask-about') ? '.ask-about' : '.picture-ask';
      const part = doc.getElementById(card.id)?.querySelector(which);
      sending = false;
      if (!part) { location.assign(r.url + '#' + card.id); return; }
      const now = waitingSig(doc);
      const outside = [...known].some(([id, sig]) => now.get(id) !== sig)
        || [...now.keys()].some(id => !known.has(id));
      const mine = document.importNode(part, true);
      ask.replaceWith(mine);
      wire(mine);
      // a picture asked folds nothing back: its line takes the focus
      const into = mine.querySelector('summary') || mine;
      if (into === mine) mine.tabIndex = -1;
      into.focus();
      known = now;
      rebase(doc, []);
      if (outside) stale(); else here = doc.body.dataset.stamp || here;
      return;
    }
    const fresh = doc.getElementById(card.id);
    if (!fresh || !fresh.querySelector('.sent, .sent-line')) {
      sending = false;
      location.assign(r.url + '#' + card.id);
      return;
    }
    const mine = document.importNode(fresh, true);
    mine.classList.add('is-collapsed');
    const link = mine.querySelector('a.next-waiting[href^="#"]');
    const next = link && document.getElementById(link.getAttribute('href').slice(1));
    // each card is named, so the others slide into the room the collapse leaves
    const cards = [...document.querySelectorAll('.entries > li[id]')];
    for (const c of cards) c.style.viewTransitionName = 'card-' + c.id;
    mine.style.viewTransitionName = 'card-' + card.id;
    // anything but the answered card gone from what waits is somebody else's change
    const now = waitingSig(doc);
    const outside = [...known].some(([id, sig]) => id !== card.id && now.get(id) !== sig)
      || [...now.keys()].some(id => !known.has(id));
    await settle(() => {
      card.replaceWith(mine);
      wire(mine);
      markTray();
      redraw(doc);
    });
    for (const c of document.querySelectorAll('.entries > li[id]')) c.style.viewTransitionName = '';
    known = now;
    rebase(doc, [card.id, ...redrawn]);
    if (outside) stale(); else here = doc.body.dataset.stamp || here;
    sending = false;
    if (!next) return;
    next.tabIndex = -1;
    next.focus({preventScroll: true});
    next.scrollIntoView({behavior: reduced() ? 'auto' : 'smooth', block: 'start'});
    history.replaceState(null, '', '#' + next.id);
    if (reduced()) return;
    next.classList.add('is-pulse');
    next.addEventListener('animationend', () => next.classList.remove('is-pulse'), {once: true});
  });
  // Change on a collapsed receipt opens the card again, in place
  document.addEventListener('click', e => {
    const sum = e.target.closest('li.is-collapsed > details > summary');
    if (!sum) return;
    const card = sum.closest('li.is-collapsed');
    settle(() => card.classList.remove('is-collapsed'));
  });
  // the tray: with batch mode on, a word, a comment or a drop on a card
  // waits in it instead of being sent; its bar at the page's foot lists
  // them, and Validate sends them all in one write. The switch and the
  // tray are kept per ledger in localStorage; without it they last as
  // long as the page
  const local = {
    get: k => { try { return localStorage.getItem(k); } catch (e) { return null; } },
    set: (k, v) => { try { localStorage.setItem(k, v); } catch (e) {} },
    drop: k => { try { localStorage.removeItem(k); } catch (e) {} },
  };
  const trayKey = 'tray:' + lid, batchKey = 'batch:' + lid;
  let batch = ledgerPage && local.get(batchKey) === '1';
  let tray = [];
  try {
    const kept = JSON.parse(local.get(trayKey) || '[]');
    if (ledgerPage && Array.isArray(kept)) tray = kept.filter(i => i && i.fields && i.card);
  } catch (e) { tray = []; }
  const keepTray = () => { if (tray.length) local.set(trayKey, JSON.stringify(tray)); else local.drop(trayKey); };
  // what a form says, if the tray takes it: a word on a piece, a comment on
  // a piece or a question (Ask about), a drop of either
  const trayKind = (f, sub) => {
    if (!f.closest('li[id]') || f.closest('.picture-ask')) return '';
    const ref = f.elements.ref ? f.elements.ref.value : '';
    const word = sub && sub.name === 'word' ? sub.value : '';
    if (/^P\d+$/.test(ref)) return word === 'drop' ? 'drop' : word ? 'word' : 'comment';
    if (/^O\d+$/.test(ref)) return f.elements.comment ? 'comment' : word === 'drop' ? 'drop' : '';
    return '';
  };
  const firstLine = s => (s || '').trim().split('\n')[0];
  const lineOf = i => {
    const text = firstLine(i.fields.text);
    if (i.kind === 'word') return i.fields.word + (text ? ' — ' + text : '');
    if (i.kind === 'drop') return text || 'no reason given';
    return text;
  };
  const kindLabel = i => i.kind === 'word' ? 'Word ' + i.fields.word : i.kind === 'drop' ? 'Drop' : 'Comment';
  // the part of a card an item came from: its fold, or the form itself
  const partOf = (card, i) => {
    const f = card.querySelectorAll('form.say')[i.form];
    if (!f || !f.elements.ref || f.elements.ref.value !== i.ref) return null;
    const fold = f.parentElement.closest('details');
    return fold && card.contains(fold) ? fold : f;
  };
  const button = (cls, label) => {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = cls;
    b.textContent = label;
    return b;
  };
  // an item's card says it is in the tray, with a Remove; its form is closed
  // as after a send. Done again whenever a card is drawn anew
  const markTray = () => {
    for (const i of tray) {
      const card = document.getElementById(i.card);
      i.gone = !card;
      if (!card || card.querySelector('.tray-line[data-item="' + i.id + '"]')) continue;
      const part = partOf(card, i);
      if (part) {
        if (part.tagName === 'DETAILS') part.open = false;
        part.hidden = true;
        part.dataset.trayed = i.id;
      }
      const line = document.createElement('p');
      line.className = 'tray-line';
      line.dataset.item = i.id;
      line.setAttribute('role', 'status');
      const what = document.createElement('span');
      what.textContent = kindLabel(i) + ' in the tray';
      const rm = button('a-untray', 'Remove');
      rm.setAttribute('aria-label', 'Remove ' + kindLabel(i).toLowerCase() + ' on ' + i.ref + ' from the tray');
      rm.addEventListener('click', () => untray(i.id, true));
      line.append(what, rm);
      const head = card.querySelector(':scope > .card-head');
      if (head) head.after(line); else card.prepend(line);
    }
  };
  let bar = null, says = '';
  const drawBar = () => {
    if (!tray.length) { if (bar) bar.remove(); bar = null; says = ''; return; }
    if (!bar) {
      bar = document.createElement('aside');
      bar.className = 'tray-bar';
      bar.setAttribute('aria-labelledby', 'tray-count');
      document.body.append(bar);
    }
    const gone = tray.filter(i => i.gone).length;
    bar.replaceChildren();
    const head = document.createElement('div');
    head.className = 'tray-head';
    const count = document.createElement('h2');
    count.id = 'tray-count';
    count.textContent = tray.length + ' in the tray';
    const acts = document.createElement('div');
    acts.className = 'tray-acts';
    const ok = button('a-validate', 'Validate');
    ok.disabled = gone > 0;
    ok.addEventListener('click', validate);
    const empty = button('a-empty', 'Empty tray');
    empty.addEventListener('click', () => confirmEmpty(acts));
    acts.append(ok, empty);
    head.append(count, acts);
    const list = document.createElement('ul');
    list.className = 'tray-items';
    for (const i of tray) {
      const li = document.createElement('li');
      li.dataset.item = i.id;
      if (i.gone) li.classList.add('is-gone');
      if (i.refused) li.classList.add('is-refused');
      const id = document.createElement('a');
      id.className = 'tag';
      id.textContent = i.ref;
      if (!i.gone) id.href = '#' + i.card;
      const kind = document.createElement('span');
      kind.className = 'tray-kind';
      kind.textContent = i.kind;
      const text = document.createElement('span');
      text.className = 'tray-text';
      text.textContent = i.gone ? 'no longer on the page' : lineOf(i);
      const rm = button('a-untray', 'Remove');
      rm.setAttribute('aria-label', 'Remove ' + i.kind + ' on ' + i.ref);
      rm.addEventListener('click', () => untray(i.id, false));
      li.append(id, kind, text, rm);
      if (i.refused) {
        const why = document.createElement('p');
        why.className = 'tray-why';
        why.textContent = i.refused;
        li.append(why);
      }
      list.append(li);
    }
    const note = document.createElement('p');
    note.className = 'tray-says';
    note.setAttribute('role', 'status');
    note.textContent = says || (gone ? 'Remove the items no longer on the page to validate.' : '');
    bar.append(head, list, note);
  };
  const toTray = (f, sub, kind) => {
    const card = f.closest('li[id]');
    const fields = {};
    for (const [k, v] of new FormData(f, sub)) {
      if (k !== 'token' && typeof v === 'string' && !(k in fields)) fields[k] = v;
    }
    const i = {id: Date.now().toString(36) + Math.random().toString(36).slice(2, 6),
               ref: fields.ref, kind, card: card.id, form: [...card.querySelectorAll('form.say')].indexOf(f), fields};
    f.reset();
    tray.push(i);
    keepTray();
    says = '';
    markTray();
    drawBar();
    const line = card.querySelector('.tray-line[data-item="' + i.id + '"] button');
    if (line) line.focus();
  };
  // Remove: the item leaves the tray, its form comes back; from a card the
  // focus goes back to what the form was, from the bar to the bar
  const untray = (id, fromCard) => {
    const at = tray.findIndex(i => i.id === id);
    if (at < 0) return;
    tray.splice(at, 1);
    keepTray();
    says = '';
    document.querySelector('.tray-line[data-item="' + id + '"]')?.remove();
    const part = document.querySelector('[data-trayed="' + id + '"]');
    if (part) { part.hidden = false; delete part.dataset.trayed; }
    drawBar();
    if (fromCard && part) (part.querySelector('summary, button') || part).focus();
    else if (bar) (bar.querySelectorAll('.tray-items .a-untray')[Math.min(at, tray.length - 1)] || bar.querySelector('.a-validate')).focus();
  };
  const emptyTray = () => {
    for (const i of [...tray]) untray(i.id, false);
  };
  // Empty asks inside the bar, never in a browser dialog
  const confirmEmpty = acts => {
    acts.replaceChildren();
    const q = document.createElement('span');
    q.className = 'tray-ask';
    q.textContent = 'Empty the tray of ' + tray.length + '?';
    const yes = button('a-empty', 'Yes, empty it');
    yes.addEventListener('click', emptyTray);
    const keep = button('a-keep', 'Keep them');
    keep.addEventListener('click', () => { drawBar(); bar.querySelector('.a-empty').focus(); });
    acts.append(q, yes, keep);
    keep.focus();
  };
  // Validate: every item in one request, one write; refused, nothing is
  // written and the tray keeps them all, the refused ones marked
  const validate = async () => {
    if (sending || !tray.length || tray.some(i => i.gone)) return;
    const token = document.querySelector('form.say input[name="token"]')?.value || '';
    sending = true;
    says = 'Sending…';
    drawBar();
    let r = null, doc = null, refused = null;
    try {
      r = await fetch('/l/' + lid + '/say-batch', {
        method: 'POST',
        credentials: 'same-origin',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: new URLSearchParams({token, items: JSON.stringify(tray.map(i => i.fields))}),
      });
      if (r.ok && r.redirected) doc = new DOMParser().parseFromString(await r.text(), 'text/html');
      else if ((r.headers.get('Content-Type') || '').startsWith('application/json')) refused = await r.json();
    } catch (err) { doc = null; }
    if (!doc) {
      sending = false;
      for (const i of tray) delete i.refused;
      for (const x of (refused && refused.items) || []) if (tray[x.item]) tray[x.item].refused = x.why;
      keepTray();
      says = refused ? refused.why : 'Not sent: the viewer did not answer' + (r ? ' (' + r.status + ')' : '') + '. The tray is kept.';
      drawBar();
      return;
    }
    const cards = [...new Set(tray.map(i => i.card))];
    tray = [];
    keepTray();
    says = '';
    const [now, outside] = outsideOf(doc, cards);
    await settle(() => {
      for (const id of cards) {
        const card = document.getElementById(id), fresh = doc.getElementById(id);
        if (!card) continue;
        if (!fresh) { card.remove(); continue; }
        const mine = document.importNode(fresh, true);
        if (/^[qp]-/.test(id) && mine.querySelector('.sent, .sent-line')) mine.classList.add('is-collapsed');
        card.replaceWith(mine);
        wire(mine);
      }
      redraw(doc);
      drawBar();
    });
    known = now;
    rebase(doc, [...cards, ...redrawn]);
    if (outside) stale(); else here = doc.body.dataset.stamp || here;
    sending = false;
  };
  // the switch, in the ledger's head: off by default, per ledger
  if (ledgerPage) {
    const head = document.querySelector('.ledger-head');
    const sw = document.createElement('div');
    sw.className = 'batch-switch';
    sw.innerHTML = '<input type="checkbox" role="switch" id="batch-mode" class="a-batch">'
      + '<label for="batch-mode">Batch mode</label><span class="batch-says" id="batch-says"></span>';
    const box = sw.querySelector('input');
    box.setAttribute('aria-describedby', 'batch-says');
    const sayMode = () => {
      box.checked = batch;
      sw.querySelector('.batch-says').textContent = batch
        ? 'words, comments and drops wait in the tray until you validate them'
        : 'each word, comment and drop is sent at once';
    };
    box.addEventListener('change', () => {
      batch = box.checked;
      local.set(batchKey, batch ? '1' : '0');
      sayMode();
    });
    sayMode();
    const at = head && (head.querySelector(':scope > .waker') || head.querySelector(':scope > nav.tiles'));
    if (at) at.before(sw); else if (head) head.append(sw);
    markTray();
    drawBar();
  }
  let live = false;
  const poll = async () => {
    try {
      const r = await fetch('/stamp', {cache: 'no-store'});
      if (r.ok) changed(await r.text());
    } catch (e) {}
    setTimeout(poll, live ? 30000 : 3000);
  };
  if (window.EventSource) {
    // a stream down for 10 s is shown, quietly: a status in the head, no
    // focus; the poll carries on meanwhile. A failed connection closes the
    // source for good, so it is opened again after 2 s, doubling to 30 s,
    // never two at once
    let es = null, paused = null, lost = 0, retry = 0, delay = 2000;
    // looked up each time: a change elsewhere draws the head anew
    const host = () => document.querySelector('.receipt, .queue-summary');
    const open = () => {
      retry = 0;
      es = new EventSource('/events?since=' + encodeURIComponent(here));
      es.addEventListener('open', () => {
        live = true; delay = 2000; clearTimeout(lost); lost = 0; clearTimeout(retry); retry = 0;
        if (paused) { paused.remove(); paused = null; }
      });
      es.addEventListener('error', () => {
        live = false;
        if (host() && !lost && !paused) {
          lost = setTimeout(() => {
            lost = 0;
            if (live || paused || !host()) return;
            paused = document.createElement('span');
            paused.className = 'live-state';
            paused.setAttribute('role', 'status');
            paused.textContent = 'Live updates paused \u2014 reconnecting';
            host().append(' ', paused);
          }, 10000);
        }
        if (es.readyState === 2 && !retry) {
          es.close();
          retry = setTimeout(open, delay);
          delay = Math.min(delay * 2, 30000);
        }
      });
      es.addEventListener('stamp', e => changed(e.data));
    };
    open();
  }
  setTimeout(poll, 3000);
})();
