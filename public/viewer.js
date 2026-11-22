
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
  // the text selected outside a form, for the quote buttons. They stay
  // hidden until a first selection, a greyed button giving no reason why;
  // after it they are enabled only while there is a selection to quote.
  // A tap on the button can clear the selection just before its click, so
  // a cleared selection disables them only after a moment
  let quote = '', seen = false, lapse = 0;
  const quotable = on => {
    for (const b of document.querySelectorAll('button.a-quote')) { b.hidden = !seen; b.disabled = !on; }
  };
  document.addEventListener('selectionchange', () => {
    const s = document.getSelection();
    const t = s ? s.toString().trim() : '';
    const n = s && s.anchorNode && (s.anchorNode.nodeType === 1 ? s.anchorNode : s.anchorNode.parentElement);
    clearTimeout(lapse);
    if (!t || (n && n.closest('form'))) {
      if (quote) lapse = setTimeout(() => { quote = ''; quotable(false); }, 400);
      return;
    }
    quote = t;
    seen = true;
    quotable(true);
  });
  // what batch mode says on the buttons and forms of a root, once the tray
  // is known (below)
  let labelBatch = () => {};
  // the controls that need script, woken in a root: the whole page on load,
  // a card swapped in after a send
  const wire = root => {
    labelBatch(root);
    // the proposed order as a list of titles moved up and down, written
    // into the comma field (the form's own, kept for a page without
    // script); a field typed in puts the ids it names first in the list
    for (const list of root.querySelectorAll('ol.order-list')) {
      const field = list.closest('details')?.querySelector('input[name="order"]');
      if (!field) continue;
      list.hidden = false;
      const rows = () => [...list.children];
      const ends = () => rows().forEach((li, at, all) => {
        li.querySelector('.a-up').disabled = at === 0;
        li.querySelector('.a-down').disabled = at === all.length - 1;
      });
      const write = () => {
        field.value = rows().map(li => li.dataset.id).join(', ');
        field.dispatchEvent(new Event('input', {bubbles: true}));
      };
      const read = () => {
        const named = field.value.split(',').map(s => s.trim()).filter(Boolean);
        const byId = new Map(rows().map(li => [li.dataset.id, li]));
        for (const id of [...named].reverse()) if (byId.has(id)) list.prepend(byId.get(id));
        ends();
      };
      list.addEventListener('click', e => {
        const b = e.target.closest('button.a-up, button.a-down');
        if (!b || b.disabled) return;
        const li = b.closest('li'), up = b.classList.contains('a-up');
        if (up) li.previousElementSibling.before(li); else li.nextElementSibling.after(li);
        ends();
        write();
        // a button at an end of the list is disabled: the focus moves to its twin
        (b.disabled ? li.querySelector(up ? '.a-down' : '.a-up') : b).focus();
      });
      field.addEventListener('input', e => { if (e.isTrusted) read(); });
      field.addEventListener('change', read);
      read();
    }
    for (const b of root.querySelectorAll('button.a-quote')) {
      b.hidden = !seen;
      b.disabled = !quote;
      // a press on the button leaves the page's selection as it is
      b.addEventListener('mousedown', e => e.preventDefault());
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
    // a comment written on an option that is not the one picked is said,
    // beside it, so that it is not mistaken for the answer's; nothing is
    // blocked, the comment goes with the answer as it is
    for (const form of root.querySelectorAll('form.say')) {
      const tiles = [...form.querySelectorAll('.choice')].filter(c => c.querySelector('textarea'));
      if (!tiles.length) continue;
      const warn = () => {
        for (const c of tiles) {
          const ta = c.querySelector('textarea');
          const off = ta.value.trim() !== '' && !c.querySelector('input[type="radio"]').checked;
          let w = c.querySelector('.comment-unchosen');
          if (off && !w) {
            w = document.createElement('p');
            w.className = 'comment-unchosen';
            w.setAttribute('role', 'status');
            w.textContent = 'This option is not your choice';
            ta.after(w);
          } else if (!off && w) w.remove();
        }
      };
      form.addEventListener('input', warn);
      form.addEventListener('change', warn);
      warn();
    }
    // a word sent while the comment box holds text carries the comment:
    // each word button says so, so that it is not taken for the word alone
    for (const form of root.querySelectorAll('form.say')) {
      const ta = form.querySelector('.comment-box textarea');
      const words = [...form.querySelectorAll('.word-choices button[name="word"]')];
      if (!ta || !words.length) continue;
      const mark = () => {
        const on = ta.value.trim() !== '';
        for (const b of words) {
          let s = b.querySelector('.with-comment');
          if (on && !s) {
            s = document.createElement('span');
            s.className = 'with-comment';
            s.textContent = '(with comment)';
            b.append(s);
          } else if (!on && s) s.remove();
        }
      };
      ta.addEventListener('input', mark);
      form.addEventListener('reset', () => setTimeout(mark));
      mark();
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
        // what reads the field (the order list, the unchosen-option line) follows it
        t.dispatchEvent(new Event('change', {bubbles: true}));
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
  // every fold around it, then shows it; a piece drawn as a row opens
  // into its card
  const reveal = () => {
    const id = decodeURIComponent(location.hash.slice(1));
    const el = id && id !== 'say-note' && document.getElementById(id);
    if (!el) return;
    for (let f = el.closest('details'); f; f = f.parentElement.closest('details')) f.open = true;
    const row = el.querySelector(':scope > details.piece-row');
    if (row) row.open = true;
    el.scrollIntoView({block: 'start'});
  };
  window.addEventListener('hashchange', reveal);
  reveal();
  // a link to the piece the address already names changes no hash: the
  // click itself opens its row again
  document.addEventListener('click', e => {
    const a = e.target.closest('a[href^="#"]');
    const el = a && document.getElementById(decodeURIComponent(a.getAttribute('href').slice(1)));
    const row = el && el.querySelector(':scope > details.piece-row');
    if (row) row.open = true;
  });
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
             ['h2[id] > .count', e => 'count:' + e.parentElement.id], ['section.waiting form.give-all', e => 'give-all:' + e.querySelector('[name=refs]').value],
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
  // change when a part above it gains or loses one; what the clock alone
  // changes is not a change to the part: a text marked [data-age] (a wait
  // age), and the key of a mockup's path (/m/k/KEY/), issued for an hour
  // from the moment the page is drawn
  const norm = html => html.replace(/tip-\d+/g, 'tip-#').replace(/(data-age(?:="")?>)[^<]*/g, '$1')
    .replace(/\/m\/k\/[^/"]+\//g, '/m/k/#/');
  // those clock texts and keys of `mine` set to those of `fresh`, in place
  // and silently, when both have the same ones; `skip` holds the parts
  // drawn on their own, whose texts are theirs. A loaded frame's or
  // image's src keeps its key: rewriting it would load the picture again
  const within = (root, sel, skip) => [...root.querySelectorAll(sel)]
    .filter(a => !skip.some(p => p !== root && p.contains(a)));
  const KEYED = '[href*="/m/k/"], [data-src*="/m/k/"]';
  const renew = (mine, fresh, skipMine = [], skipFresh = []) => {
    const a = within(mine, '[data-age]', skipMine), b = within(fresh, '[data-age]', skipFresh);
    if (a.length === b.length) a.forEach((x, i) => { if (x.textContent !== b[i].textContent) x.textContent = b[i].textContent; });
    const c = within(mine, KEYED, skipMine), d = within(fresh, KEYED, skipFresh);
    if (c.length !== d.length) return;
    c.forEach((x, i) => {
      for (const at of ['href', 'data-src']) {
        const v = d[i].getAttribute(at);
        if (v !== null && x.getAttribute(at) !== v) x.setAttribute(at, v);
      }
    });
  };
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
  // a part the user holds: a form differing from what the server sent, its
  // picture open, a tray item for it, or a send on it in flight or not
  // confirmed, whose note would go; focus alone does not hold it, it
  // follows the part drawn anew (refocus)
  const holds = el => !!el.querySelector('.send-unconfirmed, form[aria-busy="true"], form [aria-busy="true"]')
    || [...el.querySelectorAll('form textarea, form input[type="text"]')].some(t => t.value !== t.defaultValue)
    || [...el.querySelectorAll('form input[type="radio"], form input[type="checkbox"]')].some(r => r.checked !== r.defaultChecked)
    || (!!opener && el.contains(opener) && (paneOpen() || !!(dlg && dlg.open)))
    || tray.some(i => i.card === el.id || !!el.querySelector('[id="' + CSS.escape(i.card) + '"]'));
  const foldsOf = root => [...(root.matches('details[id]') ? [root] : []), ...root.querySelectorAll('details[id]')];
  // a part drawn anew in place of `old`: the folds the user opened or
  // closed stay so, a collapsed receipt stays collapsed, and what the
  // script added to the head moves into the new one
  // the batch switch, once the page has drawn it (below): what puts it
  // into a head drawn anew
  let placeSwitch = () => {};
  // what focus is on inside a part, before the part is drawn anew: its
  // id, its name and value for an input, its place among the part's
  // focusable elements
  const FOCUSABLE = 'a[href], button, input:not([type="hidden"]), select, textarea, summary, iframe, [tabindex]';
  const focusOf = old => {
    const at = document.activeElement;
    if (!at || at === document.body || !old.contains(at)) return null;
    return {self: at === old, id: at.id, name: at.matches('input') ? at.name : '', value: at.value,
            index: [...old.querySelectorAll(FOCUSABLE)].indexOf(at)};
  };
  // focus back on the counterpart in the part drawn anew, else on the
  // part itself; the window does not scroll for it
  const refocus = (mine, was) => {
    if (!was) return;
    const list = [...mine.querySelectorAll(FOCUSABLE)];
    let to = was.self ? mine : null;
    if (!to && was.id) to = mine.id === was.id ? mine : mine.querySelector('[id="' + CSS.escape(was.id) + '"]');
    if (!to && was.name) to = [...mine.querySelectorAll('input')].find(i => i.name === was.name && i.value === was.value) || null;
    if (!to && was.index >= 0 && was.index < list.length) to = list[was.index];
    if (!to) { to = mine; mine.tabIndex = -1; }
    to.focus({preventScroll: true});
  };
  const swapPart = (old, fresh) => {
    const mine = document.importNode(fresh, true);
    foldsIn(mine);
    const open = new Map(foldsOf(old).map(d => [d.id, d.open]));
    for (const d of foldsOf(mine)) if (open.has(d.id)) d.open = open.get(d.id);
    if (old.classList.contains('is-collapsed') && mine.querySelector('.sent, .sent-line')) mine.classList.add('is-collapsed');
    if (old.matches('.ledger-head')) placeSwitch(mine);
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
  // the sections of a part the reader sees a label on, by that label:
  // [selector, label, or how to read it off the section]
  const label = t => { t = t.trim().replace(/\s+/g, ' '); return t.charAt(0).toLowerCase() + t.slice(1); };
  const SECTIONS = [
    [':scope > .text, .card-head > .text, .piece-row > summary > .text', 'title'],
    ['.tag.status', 'status'],
    ['.facet', s => label(s.querySelector('dt')?.textContent || '')],
    ['dl.case > dt', s => label(s.textContent)],
    ['.raid-part.risk', 'risk'],
    ['details.covers, details.refs', s => label(s.querySelector('summary')?.textContent || '')],
    ['fieldset', 'choices'],
    ['figure.mockup, .mock-strip, .picture-ask', 'picture'],
    ['.word-evidence', 'evidence'],
  ];
  // a dl's term goes with the descriptions after it
  const sectionHtml = s => {
    if (!s.matches('dt')) return norm(s.outerHTML);
    let html = s.outerHTML;
    for (let d = s.nextElementSibling; d && d.matches('dd'); d = d.nextElementSibling) html += d.outerHTML;
    return norm(html);
  };
  const sectionsOf = part => {
    const out = new Map(), els = [];
    for (const [sel, name] of SECTIONS) {
      for (const s of part.querySelectorAll(sel)) {
        const n = typeof name === 'string' ? name : name(s);
        if (!n) continue;
        out.set(n, (out.get(n) || '') + sectionHtml(s));
        els.push(s);
        if (s.matches('dt')) for (let d = s.nextElementSibling; d && d.matches('dd'); d = d.nextElementSibling) els.push(d);
      }
    }
    return [out, els];
  };
  const parse = html => { const t = document.createElement('template'); t.innerHTML = html; return t.content.firstElementChild; };
  // what the line says: the labelled sections that differ between the part
  // as the server sent it and as it has it now, three at most; 'and more'
  // for a fourth, or for a change outside every labelled section
  const changeText = (key, fresh) => {
    if (!fresh) return 'Removed since you started';
    const was = last.parts.has(key) ? parse(last.parts.get(key)) : null;
    if (!was) return 'Changed since you started';
    const now = parse(norm(fresh.outerHTML));
    const [a, aEls] = sectionsOf(was), [b, bEls] = sectionsOf(now);
    const names = [...new Set([...a.keys(), ...b.keys()])].filter(n => a.get(n) !== b.get(n));
    for (const s of [...aEls, ...bEls]) s.remove();
    const rest = was.outerHTML !== now.outerHTML;
    if (!names.length) return 'Changed since you started';
    const more = names.length > 3 || rest;
    return 'Changed since you started: ' + names.slice(0, 3).join(', ') + (more ? ' and more' : '');
  };
  const flag = (key, el, fresh) => {
    pending.set(key, fresh);
    const said = flags.get(key);
    if (said?.isConnected) { said.querySelector('span').textContent = changeText(key, fresh); return; }
    const line = document.createElement(el.matches('tr') ? 'div' : 'p');
    line.className = 'changed-line';
    line.setAttribute('role', 'status');
    const what = document.createElement('span');
    what.textContent = changeText(key, fresh);
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
        const was = focusOf(mine);
        mine = swapPart(mine, el);
        refocus(mine, was);
        now.set(k, mine);
      } else if (mine) {
        if (pending.has(k)) unflag(k);
        renew(mine, el);
      }
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
    renew(document.querySelector('main'), mainNew, [...now.values()], [...parts.values()]);
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
  // every group form is a part of its own, keyed by the pieces it names: the
  // ones the page fetched replace those last shown
  const rebaseGroups = parts => {
    for (const k of [...last.parts.keys()]) if (k.startsWith('give-all:')) last.parts.delete(k);
    for (const [k, el] of parts) if (k.startsWith('give-all:')) last.parts.set(k, norm(el.outerHTML));
  };
  const rebase = (doc, keys) => {
    const mainNew = last && doc.querySelector('main');
    if (!mainNew) return;
    const parts = partsOf(mainNew);
    last.skel = skeleton(mainNew);
    for (const k of keys) {
      if (k === 'give-all') rebaseGroups(parts);
      else if (parts.has(k)) last.parts.set(k, norm(parts.get(k).outerHTML)); else last.parts.delete(k);
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
    // the one-click forms for sets of pieces come and go with what still
    // waits: a word sent on one card leaves a form naming pieces already
    // given. A form the server draws as shown stays as it is.
    const bars = [...document.querySelectorAll(giveAll)], fresh = [...doc.querySelectorAll(giveAll)];
    const shown = new Map(bars.map(f => [f.outerHTML, f]));
    const kept = fresh.map(f => shown.get(f.outerHTML));
    for (const f of bars) if (!kept.includes(f)) f.remove();
    let at = document.querySelector('section.waiting > h2');
    fresh.forEach((f, i) => {
      const el = kept[i] || document.importNode(f, true);
      if (at && at.nextElementSibling !== el) at.after(el);
      at = el;
    });
    // the head's count of sent entries nothing wakes a session for grows
    // with each send, and comes or goes with the first and the last
    const unread = document.querySelector('.ledger-head > .waker-unread'), now = doc.querySelector('.ledger-head > .waker-unread');
    const actions = document.querySelector('.ledger-head > .ledger-actions');
    if (unread && !now) unread.remove();
    else if (unread && now) unread.replaceWith(document.importNode(now, true));
    else if (now && actions) actions.after(document.importNode(now, true));
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
    if (sending || f.dataset.unconfirmed) return;
    sending = true;
    // while the send is out the card's submit buttons are held: the one
    // pressed says Sending, the others wait; the drafts stay editable
    const held = [];
    // a disabled button drops the focus, which keeps the card's own form
    // as the user's while a change elsewhere is drawn (holds()): it goes
    // back to the pressed button with the rest
    const focused = document.activeElement === e.submitter;
    const hold = () => {
      for (const b of card.querySelectorAll('form.say button[type="submit"]:not(:disabled)')) {
        const text = b === e.submitter
          ? [...b.childNodes].filter(n => n.nodeType === 3 && n.nodeValue.trim()).pop() : null;
        held.push({b, text, was: text && text.nodeValue});
        if (text) {
          text.nodeValue = 'Sending…';
          b.setAttribute('aria-busy', 'true');
        }
        b.disabled = true;
      }
    };
    const release = () => {
      for (const {b, text, was} of held.splice(0)) {
        if (text) text.nodeValue = was;
        b.removeAttribute('aria-busy');
        b.disabled = false;
      }
      if (focused && e.submitter.isConnected && document.activeElement !== e.submitter) e.submitter.focus({preventScroll: true});
    };
    const plain = () => {
      sending = false;
      release();
      f.dataset.plain = '1';
      f.requestSubmit(e.submitter);
    };
    // a send that got no answer may have landed: the form is not posted
    // again by itself, the card says so and offers a Check against the
    // page, which turns into Retry once the send is seen not to be there
    const sentText = c => [...c.querySelectorAll('.sent, .sent-line, .asked-line')].map(x => x.textContent).join('|');
    const partIn = c => {
      const which = f.closest('.ask-about') ? '.ask-about' : f.closest('.picture-ask') ? '.picture-ask' : '';
      return which ? c?.querySelector(which) : c;
    };
    const unconfirmed = () => {
      sending = false;
      release();
      f.dataset.unconfirmed = '1';
      const note = document.createElement('p');
      note.className = 'send-unconfirmed';
      note.dataset.key = 'unconfirmed-' + card.id;
      note.setAttribute('role', 'alert');
      const says = document.createElement('span');
      says.textContent = 'Delivery unconfirmed: the viewer did not answer, so the send may or may not have landed. Your draft is kept.';
      const act = document.createElement('button');
      act.type = 'button';
      act.className = 'a-check';
      act.textContent = 'Check';
      note.append(says, ' ', act);
      f.querySelector('.send-unconfirmed')?.remove();
      f.append(note);
      let retry = false;
      act.addEventListener('click', async () => {
        if (retry) { delete f.dataset.unconfirmed; note.remove(); f.requestSubmit(e.submitter); return; }
        act.disabled = true;
        says.textContent = 'Checking…';
        let page = null;
        try {
          const g = await fetch(location.pathname + location.search, {credentials: 'same-origin', cache: 'no-store'});
          if (g.ok) page = new DOMParser().parseFromString(await g.text(), 'text/html');
        } catch (err) { page = null; }
        act.disabled = false;
        const fresh = page && partIn(page.getElementById(card.id));
        if (!fresh) { says.textContent = 'Delivery unconfirmed: the page could not be read to check. Your draft is kept.'; return; }
        if (sentText(fresh) !== sentText(partIn(card))) {
          delete f.dataset.unconfirmed;
          note.remove();
          sending = true;
          await land(page, location.href);
          return;
        }
        retry = true;
        act.textContent = 'Retry';
        says.textContent = 'Not delivered: nothing of it is on the page. Your draft is kept.';
      });
    };
    let doc = null, r = null;
    try {
      const body = new URLSearchParams(new FormData(f, e.submitter));
      hold();
      r = await fetch(f.action, {
        method: 'POST',
        credentials: 'same-origin',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body,
      });
      if (r.ok && r.redirected) doc = new DOMParser().parseFromString(await r.text(), 'text/html');
    } catch (err) { doc = null; }
    const land = async (doc, url) => {
      // a question asked about a card, or a picture asked of it, leaves it
      // answerable: only that part is drawn again, so an answer being
      // written on the card stays
      const ask = f.closest('.ask-about, .picture-ask');
      if (ask) {
        const which = ask.matches('.ask-about') ? '.ask-about' : '.picture-ask';
        const part = doc.getElementById(card.id)?.querySelector(which);
        sending = false;
        release();
        if (!part) { location.assign(url + '#' + card.id); return; }
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
        location.assign(url + '#' + card.id);
        return;
      }
      const mine = document.importNode(fresh, true);
      mine.classList.add('is-collapsed');
      const link = mine.querySelector('a.next-waiting[href^="#"]');
      const next = link && document.getElementById(link.getAttribute('href').slice(1));
      // the cards near the answered one are named, so they slide into the room the collapse
      // leaves; naming every card of a long page would delay the scroll by seconds
      const reach = innerHeight * 2, top = card.getBoundingClientRect().top;
      for (const c of document.querySelectorAll('.entries > li[id]')) {
        const r = c.getBoundingClientRect();
        if (r.bottom > top - reach && r.top < top + reach) c.style.viewTransitionName = 'card-' + c.id;
      }
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
      // nothing left waiting on the user: the receipt's line says so, read
      // out politely, and takes the focus
      if (!next) { mine.querySelector('.next-waiting.is-none')?.focus(); return; }
      next.tabIndex = -1;
      next.focus({preventScroll: true});
      next.scrollIntoView({behavior: reduced() ? 'auto' : 'smooth', block: 'start'});
      history.replaceState(null, '', '#' + next.id);
      if (reduced()) return;
      next.classList.add('is-pulse');
      next.addEventListener('animationend', () => next.classList.remove('is-pulse'), {once: true});
    };
    if (!doc) return r && r.status >= 400 && r.status < 500 ? plain() : unconfirmed();
    return land(doc, r.url);
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
  // them, and Send all sends them all in one write. The switch and the
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
  // with batch mode on, a button whose act goes to the tray says so
  // ("Commit to tray"), and an answer form, which the tray does not take,
  // says its answer still goes at once
  labelBatch = root => {
    for (const f of root.querySelectorAll('form.say')) {
      if (!/\/say$/.test(new URL(f.action).pathname)) continue;
      const subs = [...f.querySelectorAll('button[type="submit"]')];
      // the label is the button's last text, after its icon: rewritten in
      // place, so that what it says and its accessible name stay one text
      for (const b of subs) {
        const label = [...b.childNodes].filter(n => n.nodeType === 3 && n.nodeValue.trim()).pop();
        const kind = label && trayKind(f, b);
        if (!kind) continue;
        if (!('label' in b.dataset)) b.dataset.label = label.nodeValue;
        // a drop to the tray is no request yet: "Drop P2 to tray"
        const said = kind === 'drop' ? 'Drop ' + f.elements.ref.value : b.dataset.label;
        label.nodeValue = batch ? said + ' to tray' : b.dataset.label;
      }
      const answer = /^O\d+$/.test(f.elements.ref ? f.elements.ref.value : '') && f.closest('li[id]')
        && !f.closest('.picture-ask') && subs.length && subs.every(b => !trayKind(f, b));
      if (!answer) continue;
      let n = f.querySelector(':scope > .batch-at-once');
      if (!n) {
        n = document.createElement('p');
        n.className = 'batch-at-once';
        n.textContent = 'Batch mode is on: this answer is still sent at once, not put in the tray.';
        const row = f.querySelector(':scope > .actions');
        if (row) row.before(n); else f.append(n);
      }
      n.hidden = !batch;
    }
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
    const ok = button('a-validate', 'Send all (' + tray.length + ')');
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
    note.textContent = says || (gone ? 'Remove the items no longer on the page to send them all.' : '');
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
    if (!sending) says = '';
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
  // Send all: every item in one request, one write; refused, nothing is
  // written and the tray keeps them all, the refused ones marked
  const validate = async () => {
    if (sending || !tray.length || tray.some(i => i.gone)) return;
    const token = document.querySelector('form.say input[name="token"]')?.value || '';
    // what is sent is what the tray holds now: an item added while the send
    // is out stays in the tray, and only these leave it
    const snap = [...tray];
    sending = true;
    says = 'Sending…';
    drawBar();
    let r = null, doc = null, refused = null;
    try {
      r = await fetch('/l/' + lid + '/say-batch', {
        method: 'POST',
        credentials: 'same-origin',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: new URLSearchParams({token, items: JSON.stringify(snap.map(i => i.fields))}),
      });
      if (r.ok && r.redirected) doc = new DOMParser().parseFromString(await r.text(), 'text/html');
      else if ((r.headers.get('Content-Type') || '').startsWith('application/json')) refused = await r.json();
    } catch (err) { doc = null; }
    if (!doc) {
      sending = false;
      for (const i of snap) delete i.refused;
      for (const x of (refused && refused.items) || []) if (snap[x.item]) snap[x.item].refused = x.why;
      keepTray();
      says = refused ? refused.why : 'Not sent: the viewer did not answer' + (r ? ' (' + r.status + ')' : '') + '. The tray is kept.';
      drawBar();
      return;
    }
    const cards = [...new Set(snap.map(i => i.card))];
    tray = tray.filter(i => !snap.includes(i));
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
      markTray();
      drawBar();
    });
    known = now;
    rebase(doc, [...cards, ...redrawn]);
    if (outside) stale(); else here = doc.body.dataset.stamp || here;
    sending = false;
  };
  // the switch, in the head's Details with the waker: off by default, per
  // ledger; the fold's summary says its state beside the waker's
  if (ledgerPage) {
    const head = document.querySelector('.ledger-head');
    const state = document.createElement('span');
    state.className = 'batch-state';
    const sw = document.createElement('div');
    sw.className = 'batch-switch';
    sw.innerHTML = '<input type="checkbox" role="switch" id="batch-mode" class="a-batch">'
      + '<label for="batch-mode">Batch mode</label><span class="batch-says" id="batch-says"></span>';
    const box = sw.querySelector('input');
    box.setAttribute('aria-describedby', 'batch-says');
    const sayMode = () => {
      box.checked = batch;
      sw.querySelector('.batch-says').textContent = batch
        ? 'words, comments and drops wait in the tray until you send them all'
        : 'each word, comment and drop is sent at once';
      state.textContent = ', batch ' + (batch ? 'on' : 'off');
      labelBatch(document);
    };
    box.addEventListener('change', () => {
      batch = box.checked;
      local.set(batchKey, batch ? '1' : '0');
      sayMode();
    });
    sayMode();
    placeSwitch = into => {
      const fold = into && into.querySelector(':scope > .ledger-details');
      if (!fold) return;
      fold.querySelector(':scope > summary').append(state);
      const at = fold.querySelector(':scope > .waker');
      if (at) at.before(sw); else fold.append(sw);
    };
    placeSwitch(head);
    markTray();
    drawBar();
  }
  let live = false;
  // a ledger page watches its own ledger's stamp, which a write to another
  // ledger leaves alone; the index watches every ledger's
  const watched = ledgerPage ? 'lid=' + encodeURIComponent(lid) : '';
  const poll = async () => {
    try {
      const r = await fetch('/stamp' + (watched ? '?' + watched : ''), {cache: 'no-store'});
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
      es = new EventSource('/events?since=' + encodeURIComponent(here) + (watched ? '&' + watched : ''));
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
