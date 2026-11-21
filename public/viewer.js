
(() => {
  let here = document.body.dataset.stamp;
  // the side list and the goal's words are folds on a narrow page and open
  // while the page is wide; narrow, each keeps its own state
  const wide = matchMedia('(min-width: 64rem)');
  const widthFolds = [...document.querySelectorAll('details.sections, .ledger-main > .goal > .goal-words')];
  for (const d of document.querySelectorAll('details[id]')) {
    try {
      const v = sessionStorage.getItem('open:' + d.id);
      if (v !== null) d.open = v === '1';
    } catch (e) {}
    d.addEventListener('toggle', () => {
      if (widthFolds.includes(d) && wide.matches) return;
      try { sessionStorage.setItem('open:' + d.id, d.open ? '1' : '0'); } catch (e) {}
    });
  }
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
  const draftForms = () => {
    const seen = {};
    const out = [];
    for (const f of document.querySelectorAll('form.say')) {
      const ref = f.elements.ref && f.elements.ref.value;
      if (!ref || f.closest('.drop-fold')) continue;
      seen[ref] = (seen[ref] || 0) + 1;
      out.push([f, 'draft:' + lid + ':' + ref + (seen[ref] > 1 ? '#' + seen[ref] : '')]);
    }
    return out;
  };
  const keepDrafts = () => {
    for (const [f, key] of draftForms()) {
      const radios = {}, texts = {};
      for (const r of f.querySelectorAll('input[type="radio"]')) {
        if (r.checked && r.checked !== r.defaultChecked) radios[r.name] = r.value;
      }
      for (const t of f.querySelectorAll('textarea, input[type="text"]')) {
        if (t.value !== t.defaultValue) texts[t.name] = t.value;
      }
      try {
        if (Object.keys(radios).length || Object.keys(texts).length) {
          sessionStorage.setItem(key, JSON.stringify({radios, texts}));
        } else sessionStorage.removeItem(key);
      } catch (e) {}
    }
  };
  const letterOf = v => v.split(' = ')[0].replace(/^(pick|note):/, '');
  for (const [f, key] of draftForms()) {
    f.addEventListener('submit', () => { try { sessionStorage.removeItem(key); } catch (e) {} });
    let d = null;
    try {
      d = JSON.parse(sessionStorage.getItem(key) || 'null');
      sessionStorage.removeItem(key);
    } catch (e) { d = null; }
    if (!d) continue;
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
    if (kept.length) lines.push('Kept from before the refresh: ' + kept.join(' and ') + ', not sent yet.');
    for (const g of gone) lines.push(g + ' is no longer offered; nothing was sent.');
    if (!lines.length) continue;
    const p = document.createElement('p');
    p.className = 'draft-note';
    p.setAttribute('role', 'status');
    p.textContent = lines.join(' ');
    f.prepend(p);
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
  const changed = stamp => {
    if (sending || stamp.trim() === here) return;
    // a ledger page is being read: it says so and waits; the index is a
    // queue to glance at and reloads quietly unless a draft or pane holds it
    if (ledgerPage || dirty()) stale(); else location.reload();
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
  // the waiting cards as the server last showed them: id, title and question
  const waitingSig = root => new Map([...root.querySelectorAll('section.waiting > ul.entries:not(.answered) > li[id]')]
    .map(li => [li.id, [li.querySelector('.card-head .text')?.textContent, li.querySelector(':scope > .detail')?.textContent].join('|')]));
  let known = waitingSig(document);
  const settle = fn => {
    if (reduced() || !document.startViewTransition) { fn(); return Promise.resolve(); }
    return document.startViewTransition(fn).finished.catch(() => {});
  };
  document.addEventListener('submit', async e => {
    const f = e.target;
    if (!f.matches || !f.matches('form.say') || f.dataset.plain) return;
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
    // a question asked about a card leaves it answerable: only its ask part
    // is drawn again, so an answer being written on the card stays
    const ask = f.closest('.ask-about');
    if (ask) {
      const part = doc.getElementById(card.id)?.querySelector('.ask-about');
      sending = false;
      if (!part) { location.assign(r.url + '#' + card.id); return; }
      const now = waitingSig(doc);
      const outside = [...known].some(([id, sig]) => now.get(id) !== sig)
        || [...now.keys()].some(id => !known.has(id));
      const mine = document.importNode(part, true);
      ask.replaceWith(mine);
      wire(mine);
      mine.querySelector('summary').focus();
      known = now;
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
    });
    for (const c of document.querySelectorAll('.entries > li[id]')) c.style.viewTransitionName = '';
    known = now;
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
    const host = document.querySelector('.receipt, .queue-summary');
    const open = () => {
      retry = 0;
      es = new EventSource('/events?since=' + encodeURIComponent(here));
      es.addEventListener('open', () => {
        live = true; delay = 2000; clearTimeout(lost); lost = 0; clearTimeout(retry); retry = 0;
        if (paused) { paused.remove(); paused = null; }
      });
      es.addEventListener('error', () => {
        live = false;
        if (host && !lost && !paused) {
          lost = setTimeout(() => {
            lost = 0;
            if (live || paused) return;
            paused = document.createElement('span');
            paused.className = 'live-state';
            paused.setAttribute('role', 'status');
            paused.textContent = 'Live updates paused \u2014 reconnecting';
            host.append(' ', paused);
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
