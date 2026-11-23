// viewer.cjs -- what the viewer's page script and stylesheet do in a real
// browser, which the HTML checks cannot see: run by check-ledger-browser.sh
// as `node viewer.cjs BASE LEDGER BROWSER`, BROWSER chrome or firefox.
// Prints one ok/FAIL line per check; exit 1 on any FAIL.
const pw = require(process.env.PLAYWRIGHT_CORE);
const path = require('path');
const { execFileSync } = require('child_process');
const [base, ledger, which] = process.argv.slice(2);

(async () => {
  let fails = 0;
  const t = (n, ok) => { console.log((ok ? 'ok   ' : 'FAIL ') + which + ': ' + n); if (!ok) fails++; };
  // a change made as anyone else makes it: bin/ledger's words against the journal in LEDGER_JOURNAL
  const run = (...words) => execFileSync(path.join(__dirname, '../../bin/ledger'), [words[0], ledger, ...words.slice(1)],
    {env: process.env, stdio: ['ignore', 'ignore', 'inherit']});
  // a send taken back: the test journal's newest event, and a rewind to it (test/support/fixture_rewind.rb)
  const rewinder = (...words) => execFileSync('bundle', ['exec', 'ruby', 'test/support/fixture_rewind.rb', words[0], ledger, ...words.slice(1)],
    {cwd: path.join(__dirname, '../..'), env: process.env, encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit']}).trim();
  const mark = () => rewinder('mark');
  const rewind = to => rewinder('rewind', to);
  const since = to => Number(rewinder('since', to));
  let touched = 0;
  const touch = () => run('fact', 'browser check touch ' + (++touched) + ' — viewer.cjs');
  const b = which === 'chrome'
    ? await pw.chromium.launch({executablePath: process.env.CHROME})
    : await pw.firefox.launch({channel: 'moz-firefox', executablePath: process.env.FIREFOX});
  const p = await b.newPage({viewport: {width: 1300, height: 900}});
  const errors = [];
  p.on('pageerror', e => errors.push(String(e)));
  // a 500 the checks answer themselves (failing, below) is not a failed request
  p.on('response', r => { if (r.status() >= 400 && r.headers()['x-check'] !== 'fallback') errors.push(r.status() + ' ' + r.url()); });
  // the page's background fetch of itself answers 500: the way to the
  // status a page says in place when it cannot read itself again; the
  // page's own loads go through
  const failing = route => route.request().resourceType() === 'fetch'
    ? route.fulfill({status: 500, headers: {'x-check': 'fallback'}, body: 'refused by the check'}) : route.continue();

  await p.goto(base + '/');
  const href = await p.getAttribute('ol.queue a.answer', 'href');
  t('index queues O1 with its card link', /#q-O1$/.test(href || ''));
  const page = href.split('#')[0];
  await p.goto(base + page);

  const s = await p.evaluate(() => ({
    shadow: getComputedStyle(document.querySelector('.tiles > a')).boxShadow,
    bullets: getComputedStyle(document.querySelector('.md ul') || document.body).listStyleType,
    next: document.querySelector('.next-step')?.textContent || '',
    waiting: document.querySelector('#waiting .count')?.textContent,
    sent: !!document.querySelector('#sent + ul #q-O3'),
    head: !!document.querySelector('#q-O1 > .card-head > h3.text'),
    quoteOff: [...document.querySelectorAll('button.a-quote')].every(x => x.hidden && x.disabled && !x.checkVisibility()),
    figure: !!document.querySelector('#q-O1 pre.figure-text'),
  }));
  t('shadows render (light-dark holds colours only)', s.shadow !== 'none');
  t('Markdown lists keep their bullets', s.bullets === 'disc');
  t('the next step names O1', /^Answer O1:/.test(s.next));
  // O1 to answer and P4's commit, deploy to give; O3 answered and sent
  t('an answered question is the session\'s turn', s.sent && s.waiting === '2');
  t('id and title one card head', s.head);
  t('text figure drawn in the card', s.figure);
  // N7: no greyed button with no reason: the quote button is hidden (and disabled) until a selection
  t('quote hidden until a selection', s.quoteOff);
// A1: an id is used once, so each label names its own control
t('A1: no id repeats on the ledger page', await p.evaluate(() => {
  const seen = new Set();
  return [...document.querySelectorAll('[id]')].every(x => !seen.has(x.id) && seen.add(x.id));
}));
// A2: the status pill opens from a target of at least 24 px each way
t('A2: the status pill\'s summary is at least 24 px', await p.evaluate(() => {
  const sums = [...document.querySelectorAll('.status-fold > summary')];
  return sums.length > 0 && sums.every(x => { const r = x.getBoundingClientRect(); return r.width >= 24 && r.height >= 24; });
}));
t('the status pill is as tall as the id chip beside it', await p.evaluate(() => {
  const pairs = [...document.querySelectorAll('.head-tags')].map(h => [h.querySelector('.status-fold'), h.querySelector('.tag.is-split')]).filter(([a, b]) => a && b);
  return pairs.length > 0 && pairs.every(([a, b]) => Math.abs(a.getBoundingClientRect().height - b.getBoundingClientRect().height) <= 0.5);
}));
  // U3: wide, the side list and the goal's words are open and the list stands beside the waiting section
  t('wide: the sections and the goal\'s words open, the list beside the page', await p.evaluate(() => {
    const sec = document.querySelector('details.sections'), w = document.querySelector('.ledger-main > .goal > .goal-words');
    const a = sec.getBoundingClientRect(), b = document.querySelector('section.waiting').getBoundingClientRect(),
          g = document.querySelector('.ledger-main').getBoundingClientRect();
    return sec.open && w.open && a.right <= b.left + 1 && b.bottom <= g.top + 1
      && getComputedStyle(sec.querySelector('summary')).display === 'none';
  }));
  // W4: the skip link is clipped until it has the focus, then shown and leads to the waiting section
  t('W4: the skip link is hidden, shown on focus, and moves to the waiting section', await p.evaluate(() => {
    const a = document.querySelector('a.skip-link'), box = () => a.getBoundingClientRect();
    const hidden = getComputedStyle(a).clipPath !== 'none' && box().width < 40;
    a.focus();
    return hidden && getComputedStyle(a).clipPath === 'none' && box().width > 100 && document.activeElement === a;
  }));
  await p.keyboard.press('Enter');
  t('W4: Enter on the skip link lands on the waiting heading', await p.evaluate(() => location.hash === '#waiting'));
  // U3: narrow, both are closed folds (their stored state is closed) and the list is a 44 px summary
  await p.setViewportSize({width: 412, height: 900});
  await p.waitForTimeout(100);
  t('narrow: the sections and the goal\'s words closed, the summary a 44 px target', await p.evaluate(() => {
    const sec = document.querySelector('details.sections'), w = document.querySelector('.ledger-main > .goal > .goal-words');
    return !sec.open && !w.open && sec.querySelector('summary').getBoundingClientRect().height >= 44;
  }));
  await p.setViewportSize({width: 1300, height: 900});
  await p.waitForTimeout(100);
  t('wide again: both open', await p.evaluate(() => document.querySelector('details.sections').open
    && document.querySelector('.ledger-main > .goal > .goal-words').open));
  // S1: on a phone the first question waiting shows its title on the first screen, the settings folded
  await p.setViewportSize({width: 390, height: 844});
  await p.goto(base + page);
  t('S1: phone 390x844: the first question\'s title is above the fold', await p.evaluate(() => {
    const h = document.querySelector('section.waiting > ul.entries > li[id^="q-"] > .card-head > .text');
    const r = h && h.getBoundingClientRect();
    return !!r && r.top >= 0 && r.bottom <= innerHeight && scrollY === 0;
  }));
  // S3: the criteria not met follow the Goal, before what follows it on the page
  t('S3: the criteria section comes directly after the Goal', await p.evaluate(() => {
    const c = document.getElementById('criteria');
    let e = c && c.previousElementSibling;
    while (e && !e.matches('h2')) e = e.previousElementSibling;
    const next = [...document.querySelectorAll('.ledger-main h2')];
    return !!e && /^Goal$/.test(e.textContent.trim()) && next.indexOf(c) === next.indexOf(e) + 1;
  }));
  // S2: a planned piece with nothing to say is one row; a click opens it into its card, and so does a link to it
  const rowP1 = () => p.evaluate(() => {
    const li = document.getElementById('piece-P1'), d = li && li.querySelector(':scope > details.piece-row');
    const card = d && d.querySelector('.row-card');
    return {row: !!d, open: !!d && d.open, high: li ? li.getBoundingClientRect().height : 0,
            card: !!card && card.checkVisibility() && !!card.querySelector('.drop-fold')};
  });
  const shut1 = await rowP1();
  await p.locator('#piece-P1 > details.piece-row > summary').click();
  const click1 = await rowP1();
  await p.locator('#piece-P1 > details.piece-row > summary').click();
  await p.evaluate(() => { location.hash = '#piece-P1'; });
  await p.waitForTimeout(200);
  const link1 = await rowP1();
  t('S2: a planned piece is one row, closed, under 80 px', shut1.row && !shut1.open && !shut1.card && shut1.high > 0 && shut1.high < 80);
  t('S2: a click on the row opens it into its card, its trash with it', click1.open && click1.card);
  t('S2: a link to #piece-P1 opens the row', link1.open && link1.card);
  await p.locator('#piece-P1 > details.piece-row > summary').click();
  await p.setViewportSize({width: 1300, height: 900});
  await p.goto(base + page);
  await p.evaluate(() => {
    // the user's words sit in a fold under the goal's title
    document.querySelector('.goal-words').open = true;
    const r = document.createRange();
    r.selectNodeContents(document.querySelector('.goal .md p'));
    getSelection().removeAllRanges();
    getSelection().addRange(r);
  });
  await p.waitForTimeout(200);
  t('quote enabled once text is selected', await p.evaluate(() => !document.querySelector('button.a-quote').disabled));
  t('N7: quote shown once text is selected', await p.evaluate(() => [...document.querySelectorAll('button.a-quote')].every(x => !x.hidden)));
  // the quote follows the selection: gone, the buttons are disabled but stay shown; back, enabled
  await p.evaluate(() => getSelection().removeAllRanges());
  await p.waitForTimeout(600);
  t('quote disabled, still shown, once the selection is cleared', await p.evaluate(() =>
    [...document.querySelectorAll('button.a-quote')].every(x => x.disabled && !x.hidden)));
  await p.evaluate(() => {
    const r = document.createRange();
    r.selectNodeContents(document.querySelector('.goal .md p'));
    getSelection().addRange(r);
  });
  await p.waitForTimeout(200);
  t('quote enabled again when text is selected again', await p.evaluate(() =>
    [...document.querySelectorAll('button.a-quote')].every(x => !x.disabled)));
  // text selected inside a comment box is the user's own draft: nothing to quote
  const box = await p.evaluate(() => {
    const li = document.querySelector('li.is-card form.say .comment-box')?.closest('li');
    li.querySelector('.comment-box').open = true;
    return '#' + li.id + ' .comment-box textarea';
  });
  await p.fill(box, 'my own draft words');
  await p.focus(box);
  await p.keyboard.press('Shift+Home');
  await p.waitForTimeout(600);
  t('a selection made inside a comment box offers no quote', await p.evaluate(() =>
    [...document.querySelectorAll('button.a-quote')].every(x => x.disabled)));
  await p.fill(box, '');
  await p.evaluate(b => { const ta = document.querySelector(b); ta.blur(); ta.closest('details').open = false; }, box);

  await p.click('.ledger-head a[href="#say-note"]');
  t('Leave a note opens the box under the goal', await p.evaluate(() => {
    const box = document.getElementById('say-note'), fold = box.closest('details');
    return fold.open && document.activeElement === box && ['goal', 'goal-done'].some(c => fold.previousElementSibling?.classList.contains(c));
  }));

  // a criterion named by a piece is a link; following one in a closed fold opens it
  t('a piece\'s criterion is a link, and the criterion links back', await p.evaluate(() => {
    const a = document.querySelector('#flight + ul a[href^="#crit-D"]');
    const c = a && document.getElementById(a.getAttribute('href').slice(1));
    return !!c && !!c.querySelector('a[href^="#piece-P"]');
  }));
  const settled = await p.evaluate(() => {
    const li = document.querySelector('details li[id^="piece-"]');
    if (!li) return null;
    li.closest('details').open = false;
    return li.id;
  });
  if (settled) {
    await p.evaluate(h => { location.hash = h; }, settled);
    await p.waitForTimeout(200);
    t('a link into a closed fold opens it', await p.evaluate(h => document.getElementById(h).closest('details').open, settled));
  }

  // an open record fold keeps space under its list, whichever fold it is
  t('record folds keep their bottom padding', await p.evaluate(() => {
    const gaps = [...document.querySelectorAll('details.done-fold')].map(f => {
      f.open = true; const ul = f.querySelector(':scope > .entries, :scope > .raid-fold');
      return f.getBoundingClientRect().bottom - ul.getBoundingClientRect().bottom;
    });
    for (const f of document.querySelectorAll('details.done-fold')) f.open = false;
    return gaps.length > 1 && gaps.every(g => g >= 12);
  }));

  // a card ending with its word or answer form keeps as much room under the panel as beside it
  const feetGaps = await p.evaluate(() => [...document.querySelectorAll('.entries > li.is-card')]
    .filter(li => li.lastElementChild?.matches('form.say') && li.lastElementChild.checkVisibility())
    .map(li => { const r = li.getBoundingClientRect(), f = li.lastElementChild.getBoundingClientRect();
      return Math.abs((r.bottom - f.bottom) - (f.left - r.left)); }));
  t(`a card's word or answer panel sits as far from the card's foot as from its sides (largest difference ${Math.max(0, ...feetGaps).toFixed(1)} px over ${feetGaps.length})`,
    feetGaps.length > 0 && feetGaps.every(d => d <= 1.5));
  // a choice's comment at its tile's foot, level across the row
  const feet = await p.evaluate(() => [...document.querySelectorAll('#q-O1 .choice')].map(c =>
    Math.round(c.getBoundingClientRect().bottom - c.querySelector(':scope > details').getBoundingClientRect().bottom)));
  t('a choice\'s comment sits at the foot of its tile', feet.length > 1 && feet.every(x => x === feet[0] && x < 16));

  t('wide: a short title and its tags on one line', await p.evaluate(() => {
    const h = document.querySelector('#flight + ul .card-head');
    const t = h.querySelector('.text').getBoundingClientRect(), g = h.querySelector('.head-tags').getBoundingClientRect();
    return g.top < t.bottom && g.left >= t.right - 1;
  }));
  // status, id, the why icon and the trash together at the end of the head:
  // the icon beside the id, then the trash one icon (24 px) apart
  const gap = await p.evaluate(() => {
    const h = [...document.querySelectorAll('#flight + ul .card-head')].find(x => x.querySelector('.drop-fold'));
    const s = h.querySelector('.tag.status').getBoundingClientRect(), d = h.querySelector('.drop-fold').getBoundingClientRect();
    const id = h.querySelector('.tag:not(.status)').getBoundingClientRect();
    const w = h.querySelector('.why-icon').getBoundingClientRect();
    // beside: as close to the id as the id is to the status
    return {gap: d.left - w.right,
            beside: w.left - id.right >= 0 && w.left - id.right <= id.left - s.right + 1,
            together: id.left - s.right < 16 && s.right <= id.left,
            end: h.getBoundingClientRect().right - d.right < 40};
  });
  t('the tags sit by the trash, one icon apart', Math.abs(gap.gap - 24) <= 1 && gap.beside && gap.together && gap.end);

  // R20: a card's status is one pill: tapping the word opens its meaning
  // inside the same pill, after the word and without repeating it
  const tag = p.locator('#flight + ul .card-head .status-fold > summary').first();
  const pill = () => tag.evaluate(el => {
    const d = el.parentElement, sy = d.querySelector('.status-says'), a = d.getBoundingClientRect(), b = sy.getBoundingClientRect();
    return {open: d.open, shown: sy.checkVisibility(), word: el.textContent, text: sy.textContent,
            inside: b.left >= a.left - 1 && b.right <= a.right + 1 && b.top >= a.top - 1 && b.bottom <= a.bottom + 1, one: d.matches('.tag.status')};
  });
  const shut = await pill();
  await tag.click();
  const opened = await pill();
  await tag.click();
  const shut2 = await pill();
// an open row keeps its drop icon in its head line, at a card's distance from the edge
const rowDrop = await p.evaluate(() => {
  const d = document.querySelector('li.is-row details.piece-row');
  if (!d) return null;
  d.open = true;
  const s = d.querySelector(':scope > summary').getBoundingClientRect(), t = d.querySelector('.row-drop .drop-fold > summary').getBoundingClientRect();
  const li = d.closest('li').getBoundingClientRect(), head = document.querySelector('li.is-card .card-head'), ct = head.querySelector('.drop-fold > summary').getBoundingClientRect();
  const r = [Math.abs((t.top + t.height / 2) - (s.top + s.height / 2)), Math.abs((li.right - t.right) - (head.getBoundingClientRect().right - ct.right))];
  d.open = false;
  return r;
});
t('an open row draws its drop icon in its head line, as far from the edge as a card does', !!rowDrop && rowDrop[0] <= 1 && rowDrop[1] <= 1, JSON.stringify(rowDrop));
  // an open drop form takes the head's full row; the id and the trash stay on the title's line
  const dropOpen = await p.evaluate(() => {
    const li = document.querySelector('.entries > li.is-card[id^="q-"]'), fold = li && li.querySelector('.card-head .drop-fold');
    if (!fold) return null;
    fold.open = true;
    const h = li.querySelector('.card-head').getBoundingClientRect(), f = fold.querySelector('form').getBoundingClientRect();
    const c = li.querySelector('.card-head .head-tags > .tag').getBoundingClientRect(), t = li.querySelector('.card-head > .text').getBoundingClientRect();
    const r = {width: f.width / h.width, below: f.top >= c.bottom, chipOnTitle: Math.abs((c.top + c.height / 2) - (t.top + t.height / 2)) < 12};
    fold.open = false;
    return r;
  });
  t("an open drop form takes the head's full row below, the id staying on the title's line",
    !!dropOpen && dropOpen.width > 0.9 && dropOpen.below && dropOpen.chipOnTitle, JSON.stringify(dropOpen));
  // a list of piece rows with no card among them is styled as one with cards:
  // an open row keeps its drop in its head line
  const rowsOnly = await p.evaluate(() => {
    const row = document.querySelector('.entries > li.is-row');
    if (!row) return null;
    const list = document.createElement('ul'); list.className = 'entries';
    const copy = row.cloneNode(true); copy.id = 'rows-only-probe'; list.append(copy);
    row.parentElement.after(list);
    copy.querySelector('details').open = true;
    const drop = copy.querySelector('.row-drop');
    const r = {pos: getComputedStyle(drop).position,
               top: drop.getBoundingClientRect().top - copy.querySelector('summary').getBoundingClientRect().top};
    list.remove();
    return r;
  });
  t("a list of rows alone keeps an open row's drop in its head line",
    !!rowsOnly && rowsOnly.pos === 'absolute' && Math.abs(rowsOnly.top) < 2, JSON.stringify(rowsOnly));
  t('R20: a status is one pill; its meaning opens inside it after the word, not repeating it, and closes again',
    !shut.open && !shut.shown && opened.open && opened.shown && opened.one && opened.inside
    && /^(planned|out)$/.test(opened.word) && opened.text.length > 10 && !opened.text.startsWith(opened.word)
    && !shut2.open && !shut2.shown);
  // the explanation closes the pill too, not only the word
  await tag.click();
  await tag.evaluate(el => el.parentElement.querySelector('.status-says').click());
  t('R20: a click on the open pill\'s explanation closes it', !(await pill()).open);
  const labelWide = await p.evaluate(() => getComputedStyle(document.querySelector('.drop-fold > summary > .drop-label')).display);
  await p.mouse.move(0, 0);
  await p.locator('.drop-fold > summary').first().focus();
  await p.keyboard.press('Shift+Tab'); await p.keyboard.press('Tab');
  const dt = await p.evaluate(() => {
    const s = document.activeElement, t = s.closest('details').nextElementSibling;
    const a = s.getBoundingClientRect(), b = t.getBoundingClientRect();
    const line = parseFloat(getComputedStyle(t).lineHeight);
    return {shown: s.tagName === 'SUMMARY' && t.classList.contains('tip') && getComputedStyle(t).display !== 'none',
            wide: b.width > 4 * a.width, lines: Math.round((b.height - 8) / line),
            centred: Math.abs((b.left + b.right) / 2 - (a.left + a.right) / 2) < 2 || b.right <= innerWidth};
  });
  t('the drop icon\'s tip shows on keyboard focus, as a line, not a column',
    dt.shown && dt.wide && dt.lines <= 2 && dt.centred);

  // a page that cannot read itself again (its fetch answers 500 here)
  // stays as it is, draft and all, and says so in place: no reload, no
  // note to press
  const liveSays = () => p.evaluate(() => {
    const l = document.querySelector('.live-state');
    return l ? {kind: l.dataset.live, role: l.getAttribute('role'), text: l.textContent.trim(),
                focus: l.contains(document.activeElement), inHead: !!l.closest('.receipt, .queue-summary')} : null;
  });
  await p.route(base + page, failing);
  await p.evaluate(() => { document.querySelector('details.order-fold').open = true; });
  await p.fill('input[name="order"]', 'P3, P1');
  await p.click('h1');
  await p.evaluate(() => { window.__mark = 1; });
  touch();
  await p.waitForFunction(() => !!document.querySelector('.live-state'), null, {timeout: 6000}).catch(() => {});
  t('a draft survives a ledger change the page cannot read, without a reload', await p.evaluate(() => window.__mark === 1
    && document.querySelector('input[name="order"]').value === 'P3, P1'));
  // V6: a ledger page being read never reloads by itself: a fetch that
  // fails is said in place, quietly, and goes once the page is read again
  await p.goto(base + page);
  // the page's place under the reader: where a heading below the head
  // stands in the window (the browser may scroll to keep it so when the
  // status widens the head), once its pictures are in
  await p.waitForTimeout(1500);
  const reach = await p.evaluate(() => { scrollTo(0, 400); window.__mark = 1; return scrollY; });
  const placed = () => p.evaluate(() => document.getElementById('flight').getBoundingClientRect().top);
  const placeWas = await placed();
  touch();
  await p.waitForFunction(() => !!document.querySelector('.live-state'), null, {timeout: 6000}).catch(() => {});
  const said = await liveSays();
  t('V6: a ledger page whose fetch fails stays (no navigation) and says "Live updates paused" in its head, a polite status, no focus taken',
    await p.evaluate(() => window.__mark === 1) && !!said && said.kind === 'paused' && said.role === 'status'
    && /^Live updates paused/.test(said.text) && !said.focus && said.inHead, JSON.stringify(said));
  const placeNow = await placed();
  t('V6: the page does not move under the reader (' + placeWas + ' -> ' + placeNow + ')', reach > 100 && Math.abs(placeNow - placeWas) <= 1);
  t('no Refresh button and no Ledger changed note anywhere', await p.evaluate(() =>
    !document.querySelector('.a-refresh, .stale-note') && !/Ledger changed/.test(document.body.textContent)));
  await p.unroute(base + page, failing);
  touch();
  await p.waitForFunction(() => !document.querySelector('.live-state'), null, {timeout: 6000}).catch(() => {});
  t('V6: the status goes by itself once the page is read again, still without a reload',
    await p.evaluate(() => window.__mark === 1 && !document.querySelector('.live-state')));
  await p.route(base + page, failing);
  // R7: with no choice picked Send is refused; a choice asking for a comment
  // opens its fold, says what to write and requires the text
  await p.goto(base + page);
  const pick = '#q-O1 input[name="choice"]';
  t('R7: Send is refused while no choice is picked', await p.evaluate(() => !document.querySelector('#q-O1 > form.say').checkValidity()));
  await p.evaluate(s => { document.querySelectorAll(s)[1].click(); }, pick);
  t('R7: picking B opens its comment, says what to write there and requires it', await p.evaluate(() => {
    const c = document.querySelectorAll('#q-O1 .choice')[1], ta = c.querySelector('textarea'), n = c.querySelector('.comment-needed');
    return c.querySelector('details').open && /^Needed for B: /.test(n.textContent) && ta.required
      && ta.getAttribute('aria-describedby') === n.id && !document.querySelector('#q-O1 > form.say').checkValidity();
  }));
  // R10: what was picked and typed, kept for the tab, comes back on a reload
  t('R10: after a reload the kept choice and comment are back, open, with a line saying so', await p.evaluate(() => {
    const lid = location.pathname.split('/')[2];
    // R7's pick is no draft here: leaving the page would save it over the one set below
    document.querySelector('#q-O1 > form.say').reset();
    sessionStorage.setItem('draft:' + lid + ':O1', JSON.stringify({radios: {choice: [...document.querySelectorAll('#q-O1 input[name="choice"]')][1].value},
      texts: {[document.querySelectorAll('#q-O1 .choice textarea')[1].name]: 'the second host'}}));
  }).then(async () => { await p.reload(); return p.evaluate(() => {
    const f = document.querySelector('#q-O1 > form.say'), n = f.querySelector('.draft-note');
    return f.querySelectorAll('input[name="choice"]')[1].checked && f.querySelectorAll('.choice textarea')[1].value === 'the second host'
      && f.querySelectorAll('.choice details')[1].open && n && n.getAttribute('role') === 'status'
      && /^Kept from before the reload: your choice B and your comment, not sent yet\./.test(n.textContent);
  }); }));
  // R10: typed and not sent, a reload keeps it by itself (saved on pagehide), with its line
  await p.evaluate(() => {
    const f = document.querySelector('#q-O1 > form.say');
    f.reset();
    const lid = location.pathname.split('/')[2];
    sessionStorage.removeItem('draft:' + lid + ':O1');
    f.querySelectorAll('.choice input[name="choice"]')[1].click();
  });
  await p.fill('#q-O1 .choice >> nth=1 >> textarea', 'typed before the reload');
  await p.reload();
  t('R10: a draft typed and not sent is back after a reload, with its line', await p.evaluate(() => {
    const f = document.querySelector('#q-O1 > form.say'), n = f.querySelector('.draft-note');
    return f.querySelectorAll('input[name="choice"]')[1].checked && f.querySelectorAll('.choice textarea')[1].value === 'typed before the reload'
      && !!n && /^Kept from before the reload: your choice B and your comment, not sent yet\./.test(n.textContent);
  }));
  // what the next checks load must not hold a draft that the next reload would keep again
  await p.evaluate(() => { document.querySelector('#q-O1 > form.say').reset(); });
  t('R10: a choice no longer offered is said, not restored', await p.evaluate(() => {
    const lid = location.pathname.split('/')[2];
    sessionStorage.setItem('draft:' + lid + ':O1', JSON.stringify({radios: {choice: 'Z = gone'}, texts: {}}));
    return lid;
  }).then(async () => { await p.reload(); return p.evaluate(() => {
    const f = document.querySelector('#q-O1 > form.say');
    return /Your choice Z is no longer offered; nothing was sent\./.test(f.querySelector('.draft-note').textContent)
      && ![...f.querySelectorAll('input[name="choice"]')].some(r => r.checked);
  }); }));
  t('R10: a send clears that item\'s draft', await p.evaluate(() => {
    const lid = location.pathname.split('/')[2], key = 'draft:' + lid + ':O1';
    sessionStorage.setItem(key, '{}');
    // a synthetic submit must not send the form (Firefox runs its default action)
    const f = document.querySelector('#q-O1 > form.say');
    f.addEventListener('submit', e => e.preventDefault());
    f.dispatchEvent(new Event('submit', {cancelable: true}));
    return sessionStorage.getItem(key) === null;
  }));
  await p.unroute(base + page, failing);
  // the index is a queue to glance at: a fetch of it that fails is said in place too
  await p.goto(base + '/');
  t('R5: a neutral id chip in the legend splits in gray: a pale letter, a solid number', await p.evaluate(() => {
    const lg = document.querySelector('#index-legend'); if (!lg) return false;
    const d = lg.closest('details'); if (d) d.open = true;
    const c = lg.querySelector('.tag.is-split'); if (!c) return false;
    const l = getComputedStyle(c.querySelector('.l')).backgroundColor, n = getComputedStyle(c.querySelector('.n')).backgroundColor;
    return l !== n && n !== 'rgba(0, 0, 0, 0)';
  }));
  await p.route(base + '/', failing);
  await p.waitForTimeout(1500);
  await p.evaluate(() => { window.__mark = 1; });
  touch();
  await p.waitForTimeout(4500);
  const idxSaid = await liveSays();
  t('V6: a clean index whose fetch fails stays (no navigation) and says "Live updates paused" beside its summary',
    await p.evaluate(() => window.__mark === 1) && !!idxSaid && idxSaid.kind === 'paused' && idxSaid.inHead);
  // the stream pushes it: within 3 s, before the 3 s fallback poll could
  await p.goto(base + '/');
  await p.waitForTimeout(1500);
  await p.evaluate(() => { window.__mark = 1; });
  touch();
  await p.waitForTimeout(2500);
  t('a clean index whose fetch fails says so within 3 s while its EventSource is open, without a reload',
    await p.evaluate(() => window.__mark === 1 && document.querySelector('.live-state')?.dataset.live === 'paused'));
  await p.unroute(base + '/', failing);
  await p.unroute(base + '/', failing);
  // V7: a clean index draws its changed rows again in place, without a reload
  await p.goto(base + '/');
  await p.waitForTimeout(1500);
  const rowOf = () => document.querySelector('tr[data-key^="r:"]').textContent;
  const rowWas = await p.evaluate(rowOf);
  await p.evaluate(() => { window.__mark = 1; });
  run('piece', 'P2', '--status', 'dropped');
  await p.waitForFunction(w => document.querySelector('tr[data-key^="r:"]').textContent !== w, rowWas, {timeout: 6000}).catch(() => {});
  t('V7: a clean index draws a changed row in place, without a reload', await p.evaluate(w =>
    window.__mark === 1 && document.querySelector('tr[data-key^="r:"]').textContent !== w, rowWas));
  run('undo');
  // V7: a ledger page draws a card changed elsewhere in place: no reload,
  // no note, and a fold open elsewhere stays open
  await p.goto(base + page);
  await p.waitForTimeout(1500);
  await p.evaluate(() => { window.__mark = 1; document.querySelector('details.done-fold[id$="-facts"]').open = true; });
  run('piece', 'P1', '--what', 'the range, documented where the API is');
  const what = () => /documented where the API is/.test(document.getElementById('piece-P1').textContent);
  await p.waitForFunction(what, null, {timeout: 6000}).catch(() => {});
  t('V7: a card changed elsewhere is drawn anew in place, without a reload or a note', await p.evaluate(what)
    && await p.evaluate(() => window.__mark === 1 && !document.querySelector('.live-state')));
  t('V7: a fold open elsewhere stays open', await p.evaluate(() => document.querySelector('details.done-fold[id$="-facts"]').open));
  run('undo');
  await p.waitForFunction(() => !/documented where the API is/.test(document.getElementById('piece-P1').textContent), null, {timeout: 6000}).catch(() => {});
  // V7: a card being written in is not drawn anew: it says it changed, and
  // its Update draws it, keeping the text
  await p.evaluate(() => { document.querySelector('#p-P4 details.comment-box').open = true; });
  await p.fill('#say-P4-word', 'my words, not sent');
  await p.click('h1');
  run('piece', 'P4', '--risk', '2/10 — the fix waits, it ships on Friday');
  await p.waitForSelector('#p-P4 .changed-line', {timeout: 6000}).catch(() => {});
  t('V7: a held card keeps its text and says "Changed since you started" as a polite status', await p.evaluate(() => {
    const c = document.getElementById('p-P4'), l = c.querySelector('.changed-line');
    return !!l && l.getAttribute('role') === 'status' && /^Changed since you started/.test(l.textContent.trim())
      && document.getElementById('say-P4-word').value === 'my words, not sent' && !/on Friday/.test(c.textContent)
      && !document.querySelector('.live-state');
  }));
  t('V7: its Update button is a 44 px target', await p.evaluate(() =>
    document.querySelector('#p-P4 .changed-line button').getBoundingClientRect().height >= 44));
  await p.click('#p-P4 .changed-line button');
  await p.waitForFunction(() => /on Friday/.test(document.getElementById('p-P4').textContent), null, {timeout: 5000}).catch(() => {});
  t('V7: Update draws the card anew and keeps the text', await p.evaluate(() => {
    const c = document.getElementById('p-P4');
    return /on Friday/.test(c.textContent) && !c.querySelector('.changed-line')
      && document.getElementById('say-P4-word').value === 'my words, not sent';
  }));
  run('undo');
  // F1: what the clock alone changes is no change: a card whose picture
  // key is renewed by a ledger write is neither drawn anew nor flagged,
  // and its link carries the new key
  await p.goto(base + page);
  await p.waitForTimeout(1500);
  const keyWas = await p.evaluate(() => { window.__card = document.getElementById('q-O1');
    return document.querySelector('#q-O1 a[href*="/m/k/"]').getAttribute('href'); });
  touch();
  await p.waitForFunction(w => document.querySelector('#q-O1 a[href*="/m/k/"]').getAttribute('href') !== w, keyWas, {timeout: 6000}).catch(() => {});
  t('F1: a card whose picture key alone is renewed is not drawn anew nor flagged, and its link has the new key', await p.evaluate(w => {
    const c = document.getElementById('q-O1');
    return c === window.__card && !c.querySelector('.changed-line') && c.querySelector('a[href*="/m/k/"]').getAttribute('href') !== w;
  }, keyWas));
  // F1: a waiting card whose only change is its wait age, focus inside it:
  // not drawn anew, not flagged, its age the new one, focus where it was.
  // A question with no picture, every event dated 4 min 55 s ago, so the
  // next minute comes in seconds
  const beforeAsk = mark();
  run('ask', 'how long?', '--title', 'Age check', '--problem', 'a wait', '--risk', '1/10 — none',
      '--choices', 'A = yes | B = no', '--recommend', 'A, simple', '--no-picture', 'a choice of words');
  rewinder('age', '295');
  // the write above can set the open page reloading by itself: a load it
  // aborts is taken again once, any other failure stands
  await p.goto(base + page).catch(async e => {
    if (!/NS_BINDING_ABORTED|ERR_ABORTED/.test(e.message)) throw e;
    await p.waitForLoadState('load').catch(() => {});
    await p.goto(base + page);
  });
  await p.waitForTimeout(1500);
  const ageWas = await p.evaluate(() => {
    const c = document.querySelector('section.waiting li[id^="q-"]:has([data-age]):not(:has(a[href*="/m/k/"]))');
    window.__card = c;
    c.querySelector('.drop-fold > summary').focus();
    return c.id + ' ' + c.querySelector('.meta [data-age]').textContent;
  });
  await p.waitForTimeout(6000 - 1500);
  touch();
  const ageNow = () => window.__card.querySelector('.meta [data-age]').textContent === '5 min';
  await p.waitForFunction(ageNow, null, {timeout: 6000}).catch(() => {});
  t('F1: a waiting card whose wait age alone changed keeps its focus, is not drawn anew nor flagged, and says the new age (' + ageWas + ')',
    await p.evaluate(() => {
      const c = window.__card;
      return c.isConnected && c.querySelector('.meta [data-age]').textContent === '5 min' && !c.querySelector('.changed-line')
        && document.activeElement === c.querySelector('.drop-fold > summary') && !document.querySelector('.live-state');
    }));
  run('restore', '--to', beforeAsk);
  // F2: focus alone does not hold a card: one changed elsewhere with focus
  // on its Drop button and no draft is drawn anew, unflagged, and the
  // button keeps focus without the page moving
  await p.goto(base + page);
  await p.waitForTimeout(1500);
  const heldWas = await p.evaluate(() => {
    const c = document.getElementById('piece-P2');
    window.__card = c;
    c.querySelector('.drop-fold > summary').focus({preventScroll: true});
    return scrollY;
  });
  run('piece', 'P2', '--risk', '3/10 — a noisy header');
  await p.waitForFunction(() => document.getElementById('piece-P2') !== window.__card, null, {timeout: 6000}).catch(() => {});
  t('F2: a card with focus on a button and no draft is drawn anew without the flag, and the button keeps focus', await p.evaluate(y => {
    const c = document.getElementById('piece-P2');
    return c !== window.__card && /a noisy header/.test(c.textContent) && !c.querySelector('.changed-line')
      && document.activeElement === c.querySelector('.drop-fold > summary') && scrollY === y;
  }, heldWas));
  run('undo');
  // F3: the changed line names what changed: a held card's plan, with
  // the redraw of its picture the same write declares, then its title
  // and risk
  await p.goto(base + page);
  await p.waitForTimeout(1500);
  await p.evaluate(() => { document.querySelector('#p-P4 details.comment-box').open = true; });
  await p.fill('#say-P4-word', 'my words on P4, not sent');
  await p.click('h1');
  const lineOf = () => document.querySelector('#p-P4 .changed-line > span')?.textContent || '';
  const flagged = () => !!document.querySelector('#p-P4 .changed-line');
  const unflagged = () => !document.querySelector('#p-P4 .changed-line');
  run('piece', 'P4', '--plan', 'commit it, then deploy the build on Monday', '--picture-pending', 'the plan moved');
  await p.waitForFunction(flagged, null, {timeout: 6000}).catch(() => {});
  const planSaid = await p.evaluate(lineOf);
  t('F3: a card with a draft, its plan changed elsewhere and its picture set to redraw, reads "Changed since you started: plan, picture and more" (' + planSaid + ')',
    planSaid === 'Changed since you started: plan, picture and more');
  run('undo');
  await p.waitForFunction(unflagged, null, {timeout: 6000}).catch(() => {});
  run('piece', 'P4', '--title', 'fix the reorder for good', '--risk', '3/10 — the fix waits longer');
  await p.waitForFunction(flagged, null, {timeout: 6000}).catch(() => {});
  const bothSaid = await p.evaluate(lineOf);
  t('F3: a card changed in title and risk reads both (' + bothSaid + ')', bothSaid === 'Changed since you started: title, risk');
  run('undo');
  await p.waitForFunction(unflagged, null, {timeout: 6000}).catch(() => {});
  await p.fill('#say-P4-word', '');
  // V7: a status change moving a section count draws the card and the
  // counts anew, with no note and no reload
  await p.goto(base + page);
  await p.waitForTimeout(1500);
  const flightWas = await p.evaluate(() => Number(document.querySelector('#flight .count').textContent));
  await p.evaluate(() => { window.__mark = 1; });
  run('piece', 'P2', '--status', 'dropped');
  await p.waitForFunction(() => !document.querySelector('#flight + ul #piece-P2'), null, {timeout: 6000}).catch(() => {});
  t('V7: a piece dropped elsewhere leaves Unfinished for the record and its count drops, no note, no reload', await p.evaluate(w =>
    window.__mark === 1 && !document.querySelector('#flight + ul #piece-P2') && !!document.querySelector('details.done-fold #piece-P2')
    && Number(document.querySelector('#flight .count').textContent) === w - 1 && !document.querySelector('.live-state'), flightWas));
  run('undo');

  // W5: a stream lost for 10 s is shown, apart from the changed note, and
  // goes when the stream returns
  const p2 = await b.newPage({viewport: {width: 1300, height: 900}});
  await p2.route('**/events*', r => r.abort());
  await p2.goto(base + page);
  await p2.waitForTimeout(6000);
  t('W5: no paused indicator before the stream has been down 10 s', await p2.locator('.live-state').count() === 0);
  await p2.waitForTimeout(6000);
  t('W5: a stream down for 10 s shows "Live updates paused" as a polite status, apart from the note', await p2.evaluate(() => {
    const l = document.querySelector('.receipt .live-state');
    return !!l && l.getAttribute('role') === 'status' && /Live updates paused/.test(l.textContent)
      && l.dataset.live === 'stream' && !l.contains(document.activeElement);
  }));
  await p2.unroute('**/events*');
  await p2.waitForTimeout(12000);
  t('W5: the indicator goes when the stream opens again', await p2.locator('.live-state').count() === 0);
  await p2.close();

  await p.goto(base + page);
  // a mockup beside the page when wide, over it when narrow
  const expand = p.locator('#q-O1 button.a-expand[data-kind="page"]');
  await expand.click();
  t('pane beside the page, sandboxed', await p.locator('aside.mock-pane').isVisible()
    && await p.getAttribute('aside.mock-pane iframe', 'sandbox') === 'allow-scripts'
    && await p.evaluate(() => document.body.classList.contains('is-paned')));
  // Full window beside Close: the pane covers the browser's viewport, not the screen; Esc steps out of it first
  await p.click('aside.mock-pane button.a-full');
  const fullOn = await p.evaluate(() => {
    const pane = document.querySelector('aside.mock-pane'), r = pane.getBoundingClientRect(),
          b = pane.querySelector('.a-full');
    return [Math.round(r.left) === 0 && Math.round(r.top) === 0 && Math.round(r.width) === document.documentElement.clientWidth
      && Math.round(r.height) === innerHeight, b.querySelector('span').textContent, b.getAttribute('aria-pressed'), !document.fullscreenElement];
  });
  t('Full window: the pane covers the browser viewport, the button says Exit full window, no screen full screen',
    fullOn[0] && fullOn[1] === 'Exit full window' && fullOn[2] === 'true' && fullOn[3]);
  await p.keyboard.press('Escape');
  t('Esc in the full window brings the pane back beside the page, still open', await p.evaluate(() => {
    const pane = document.querySelector('aside.mock-pane'), r = pane.getBoundingClientRect();
    return !pane.hidden && r.left > 0 && pane.querySelector('.a-full span').textContent === 'Full window';
  }));
  await p.keyboard.press('Escape');
  t('Esc closes it, focus back on Expand', !(await p.locator('aside.mock-pane').isVisible())
    && await p.evaluate(() => document.activeElement?.classList.contains('a-expand')));
  // the tile's own thumbnail is the button: tapping it opens the pane
  const tile = p.locator('#q-O1 figure.mock-tile > button.a-expand');
  t('a page is a tile: thumbnail frame scaled down, not clickable itself', await p.evaluate(() => {
    const f = document.querySelector('#q-O1 .mock-tile button.a-expand iframe');
    return !!f && getComputedStyle(f).pointerEvents === 'none' && f.getAttribute('aria-hidden') === 'true'
      && f.closest('button').getBoundingClientRect().width > 200;
  }));
  t('a page tile\'s frame fills its button: scaled width within 2 px', await p.evaluate(() => {
    const f = document.querySelector('#q-O1 .mock-tile button.a-expand iframe');
    return Math.abs(f.getBoundingClientRect().width - f.closest('button').clientWidth) <= 2;
  }));
  await tile.click();
  t('tapping the tile opens the pane (wide)', await p.locator('aside.mock-pane').isVisible());
  await p.keyboard.press('Escape');
  await p.setViewportSize({width: 600, height: 900});
  // the side list is a fold here: open it to measure it
  await p.evaluate(() => { document.querySelector('details.sections').open = true; });
  // narrow, the side list wraps: a piece's id still ends at the row's right edge
  const edge = await p.evaluate(() => {
    const li = document.querySelector('.question-nav li.is-piece'), a = li.querySelector('a');
    const ul = li.closest('ul').getBoundingClientRect(), tag = li.querySelector('.tag').getBoundingClientRect();
    return ul.right - tag.right - parseFloat(getComputedStyle(a).paddingInlineEnd);
  });
  t('narrow: a piece\'s id at the right edge of the side list', Math.abs(edge) <= 2);
  await p.setViewportSize({width: 400, height: 900});
  // status, id and trash are never split: one row ending at the right,
  // beside the title when there is room, else wholly below it
  const together = () => [...document.querySelectorAll('#flight + ul .card-head')].every(h => {
    const title = h.querySelector('.text').getBoundingClientRect();
    const row = [...h.querySelectorAll('.head-tags > .tag, .head-tags > .status-fold, .head-tags > .drop-fold')].map(x => x.getBoundingClientRect());
    const mid = r => r.top + r.height / 2, last = row[row.length - 1];
    const one = row.every(r => Math.abs(mid(r) - mid(last)) < 6);
    const beside = row[0].left >= title.right - 1 && last.top < title.bottom, below = row.every(r => r.top >= title.bottom - 1);
    return one && (beside || below) && h.getBoundingClientRect().right - last.right < 40;
  });
  t('phone: tags and trash together at the end, beside or below the title', await p.evaluate(together));
  t('R11: the trash shows its word Drop where the card is narrow, and not where it is wide', labelWide === 'none'
    && await p.evaluate(() => { const l = document.querySelector('.drop-fold > summary > .drop-label');
      return getComputedStyle(l).display !== 'none' && l.textContent === 'Drop'; }));
  await p.evaluate(() => { const h = document.querySelector('#flight + ul .card-head .text'); h.dataset.was = h.textContent;
    h.textContent = 'A title long enough to need the whole first line of the card on a phone screen'; });
  t('phone: a long title puts the tags below it, still together', await p.evaluate(together)
    && await p.evaluate(() => { const h = document.querySelector('#flight + ul .card-head');
      return h.querySelector('.head-tags').getBoundingClientRect().top >= h.querySelector('.text').getBoundingClientRect().bottom - 1; }));
  await p.evaluate(() => { const h = document.querySelector('#flight + ul .card-head .text'); h.textContent = h.dataset.was; });
  await p.setViewportSize({width: 600, height: 900});
  t('narrow: the words owed in equal columns, ids aligned', await p.evaluate(() => {
    const ls = [...document.querySelectorAll('.question-nav li.is-word')].map(li => li.getBoundingClientRect());
    return ls.length > 0 && ls.every(r => Math.abs(r.width - ls[0].width) < 1);
  }));
  t('narrow: the Elsewhere links one per line', await p.evaluate(() => {
    const xs = [...document.querySelectorAll('.question-nav ul.elsewhere > li')].map(li => li.getBoundingClientRect());
    return xs.length > 2 && xs.every(r => Math.abs(r.left - xs[0].left) < 1) && xs.every((r, i) => !i || r.top >= xs[i - 1].bottom - 1);
  }));
  await expand.click();
  t('narrow: a window over the page', await p.evaluate(() => document.querySelector('dialog.mock-dialog')?.open === true));
  await p.click('dialog.mock-dialog button.a-close');
  await tile.click();
  t('tapping the tile opens the dialog (narrow)', await p.evaluate(() => document.querySelector('dialog.mock-dialog')?.open === true));
  await p.click('dialog.mock-dialog button.a-close');
  t('Close shuts it', await p.evaluate(() => !document.querySelector('dialog.mock-dialog').open));
  // the drop request: trash and id chip stay on one line while it is open,
  // Cancel closes it and returns the focus to the trash
  await p.setViewportSize({width: 1300, height: 900});
  await p.goto(base + page);
  await p.locator('#p-P4 .drop-fold > summary').click();
  const row = await p.evaluate(() => {
    const c = document.querySelector('#p-P4'), q = x => c.querySelector(x).getBoundingClientRect();
    const a = q('.head-tags > .tag'), s = q('.drop-fold > summary'), f = q('.drop-fold > form');
    return {one: Math.abs((a.top + a.bottom) / 2 - (s.top + s.bottom) / 2) < 4, below: f.top >= s.bottom - 1,
            target: s.width >= 44 && s.height >= 44};
  });
  t('drop open: the id chip and the trash on one line, the form below, a 44 px trash', row.one && row.below && row.target);
  await p.locator('#p-P4 button.a-cancel').click();
  t('Cancel closes the drop fold and returns the focus to the trash', await p.evaluate(() => {
    const f = document.querySelector('#p-P4 .drop-fold');
    return !f.open && document.activeElement === f.querySelector('summary');
  }));
  // a word sent (P80): the card collapses in place into its Sent row with Change, the page moves on to the
  // next card waiting, focused, without a "Ledger changed" note; Change opens the card again in place
  let sent = mark();
  const idx = () => p.evaluate(() => [...document.querySelectorAll('.entries > li[id]')].map(l => l.id).indexOf('p-P4'));
  const at = await idx();
  const seen = () => p.evaluate(() => ({
    count: Number(document.querySelector('section.waiting > h2 .count').textContent),
    tile: Number(document.querySelector('.tiles > a .figure').textContent),
    listed: !!document.querySelector('nav.question-nav a[href="#p-P4"]'),
    step: document.querySelector('.ledger-head .next-step')?.getAttribute('href') || ''}));
  const was = await seen();
  await p.locator('#p-P4 button[name="word"][value="commit"]').click();
  await p.waitForSelector('#p-P4.is-collapsed');
  t('P80: a word sent collapses the card in place into a one-row receipt with Change', await p.evaluate(() => {
    const c = document.getElementById('p-P4'), sum = c.querySelector(':scope > details.comment-fold > summary');
    const r = c.getBoundingClientRect(), s = sum.getBoundingClientRect();
    return c.classList.contains('is-receipt') && /^You asked: Commit · sent \d\d:\d\d · not read by the session yet$/.test(c.querySelector('.sent-line').textContent.trim())
      && r.height < 130 && s.height > 0 && /Change/.test(sum.textContent) && !c.querySelector('details.comment-fold').open
      && getComputedStyle(c.querySelector('a.next-waiting')).display === 'none';
  }) && await idx() === at);
  const next = await p.evaluate(() => document.querySelector('#p-P4 a.next-waiting').getAttribute('href').slice(1));
  await p.waitForFunction(id => { const r = document.getElementById(id).getBoundingClientRect(); return r.top >= -1 && r.top < innerHeight / 3; }, next);
  t('P80: the next card waiting is in view and focused, without a new page', await p.evaluate(id => {
    const n = document.getElementById(id);
    return !!document.querySelector('#' + id) && /^Next waiting: ./.test(document.querySelector('#p-P4 a.next-waiting').textContent.trim())
      && document.activeElement === n && location.hash === '#' + id && !n.classList.contains('is-receipt');
  }, next));
  const now = await seen();
  t('P80: after a send the Waiting count and tile dropped by one, the side list lost the card, the next step moved on',
    was.listed && was.count > 0 && now.count === was.count - 1 && now.tile === was.tile - 1 && !now.listed
    && now.step !== '#p-P4');
  await p.waitForTimeout(1600);
  t('P80: the user\'s own send raises no status and no navigation', await p.evaluate(() => !document.querySelector('.live-state')));
  await p.locator('#p-P4 > details.comment-fold > summary').click();
  await p.waitForSelector('#p-P4:not(.is-collapsed)');
  t('P80: Change opens the card again in place', await p.evaluate(() => {
    const c = document.getElementById('p-P4'), f = c.querySelector('details.comment-fold');
    return !c.classList.contains('is-collapsed') && f.open && f.querySelector('form.say').getBoundingClientRect().height > 20
      && c.getBoundingClientRect().height > 130;
  }) && await idx() === at);
  rewind(sent);
  // a change made by someone else while the send is out is drawn in place
  // from the page the send came back with
  await p.goto(base + page);
  await p.evaluate(() => { window.__mark = 1; });
  await p.route('**/say', async route => {
    run('ask', '--title', 'Late question', 'anything else?', '--problem', 'asked meanwhile', '--risk', '5/10 — none',
      '--choices', 'A = a | B = b', '--recommend', 'A, fine', '--no-picture', 'text only');
    sent = mark();
    await route.continue();
  });
  await p.locator('#p-P4 button[name="word"][value="commit"]').click();
  await p.waitForSelector('#p-P4.is-collapsed');
  const late = () => [...document.querySelectorAll('section.waiting li[id^="q-"]')].some(c => /Late question/.test(c.textContent));
  await p.waitForFunction(late, null, {timeout: 5000}).catch(() => {});
  t('P80: an outside change made during the send is drawn in place, without a navigation', await p.evaluate(late)
    && await p.evaluate(() => window.__mark === 1 && document.getElementById('p-P4').classList.contains('is-collapsed')));
  await p.unroute('**/say');
  rewind(sent);
  run('undo');
  sent = mark();
  // reduced motion: no transition and no pulse, the move is a jump
  await p.emulateMedia({reducedMotion: 'reduce'});
  await p.goto(base + page);
  await p.locator('#p-P4 button[name="word"][value="commit"]').click();
  await p.waitForSelector('#p-P4.is-collapsed');
  await p.waitForFunction(id => { const r = document.getElementById(id).getBoundingClientRect(); return document.activeElement.id === id && r.top >= -1 && r.top < innerHeight / 3; }, next);
  const jump = await p.evaluate(id => {
    const n = document.getElementById(id), r = n.getBoundingClientRect();
    return {top: r.top, vh: innerHeight, y: scrollY, pulse: n.classList.contains('is-pulse')};
  }, next);
  t('P80: with reduced motion the page is already at the next card, no pulse', jump.top >= -1 && jump.top < jump.vh / 3 && !jump.pulse);
  await p.emulateMedia({reducedMotion: 'no-preference'});
  rewind(sent);
  // without script the redirect lands on the next card's anchor
  const plain = await b.newContext({javaScriptEnabled: false, viewport: {width: 1300, height: 900}});
  const q = await plain.newPage();
  await q.goto(base + page);
  await q.locator('#p-P4 button[name="word"][value="commit"]').click();
  await q.waitForURL(u => u.hash === '#' + next);
  t('P80: a send with script off lands on the next card\'s anchor', await q.evaluate(id => location.hash === '#' + id
    && document.getElementById('p-P4').classList.contains('is-receipt') && !!document.getElementById(id), next));
  await plain.close();
  rewind(sent);
  // P25: batch mode off by default; on, a word, a comment and a drop wait in the tray, each card saying so; one
  // removed, the tray kept across a reload, the rest sent by one Send all as one write; off again, sent at once
  await p.goto(base + page);
  const posts = [];
  const count = r => { if (r.method() === 'POST') posts.push(new URL(r.url()).pathname); };
  p.on('request', count);
  t('P25: batch mode is a switch in the head, off by default', await p.evaluate(() => {
    const s = document.querySelector('.ledger-head .batch-switch input[role="switch"]');
    return !!s && !s.checked && !document.querySelector('.tray-bar');
  }));
  // the switch sits in the head's Details fold
  await p.evaluate(() => { document.querySelector('.ledger-head .ledger-details').open = true; });
  await p.check('#batch-mode');
  await p.locator('#p-P4 button[name="word"][value="commit"]').click();
  await p.locator('#q-O1 .ask-about > details > summary').click();
  await p.fill('#say-O1-ask', 'which file?\nthe second line');
  await p.locator('#q-O1 .ask-about button[type="submit"]').click();
  await p.locator('#piece-P2 .drop-fold > summary').click();
  await p.locator('#piece-P2 button.a-drop').click();
  const trayed = () => p.evaluate(() => ({
    count: document.querySelector('.tray-bar h2')?.textContent,
    items: [...document.querySelectorAll('.tray-bar .tray-items > li')].map(li =>
      [li.querySelector('.tag').textContent, li.querySelector('.tray-kind').textContent, li.querySelector('.tray-text').textContent]),
    cards: [...document.querySelectorAll('.tray-line')].map(l => l.closest('li[id]').id + ' ' + l.querySelector('span').textContent),
    sticky: (() => { const b = document.querySelector('.tray-bar'); return !!b && getComputedStyle(b).position === 'sticky'
      && b.getBoundingClientRect().bottom <= innerHeight + 1 && b.getBoundingClientRect().bottom > innerHeight - 48; })(),
    closed: !!document.querySelector('#p-P4 form.say[hidden]') && document.querySelector('#piece-P2 .drop-fold').hidden
      && document.querySelector('#q-O1 .ask-about > details').hidden}));
  const held = await trayed();
  t('P25: nothing is sent while batch mode is on', posts.length === 0);
  t('P25: the bar says 3 in the tray, each item its id, kind and one line of text, sticky at the foot',
    held.count === '3 in the tray' && held.sticky && JSON.stringify(held.items) === JSON.stringify(
      [['P4', 'word', 'commit'], ['O1', 'comment', 'which file?'], ['P2', 'drop', 'no reason given']]));
  t('P25: each card says in the tray, its form closed', held.closed && JSON.stringify(held.cards) === JSON.stringify(
    ['q-O1 Comment in the tray', 'p-P4 Word commit in the tray', 'piece-P2 Drop in the tray']));
  await p.locator('#q-O1 .tray-line button.a-untray').click();
  t('P25: Remove on a card takes the item out and gives the form back', await p.evaluate(() =>
    !document.querySelector('#q-O1 .tray-line') && !document.querySelector('#q-O1 .ask-about > details').hidden
    && document.querySelector('.tray-bar h2').textContent === '2 in the tray'));
  await p.reload();
  const back = await trayed();
  t('P25: the tray and its cards are kept across a reload, batch mode still on',
    back.count === '2 in the tray' && back.cards.length === 2 && await p.isChecked('#batch-mode'));
  await p.locator('.tray-bar .a-empty').click();
  t('P25: Empty asks inside the bar, and Keep keeps them', await p.evaluate(() =>
    /Empty the tray of 2\?/.test(document.querySelector('.tray-bar .tray-acts').textContent))
    && await p.locator('.tray-bar .a-keep').click().then(() => p.evaluate(() =>
      document.querySelectorAll('.tray-bar .tray-items > li').length === 2)));
  sent = mark();
  await p.locator('.tray-bar .a-validate').click();
  await p.waitForSelector('.tray-bar', {state: 'detached'});
  t('P25: Send all sends the rest in one request, one write, and empties the tray', JSON.stringify(posts) ===
    JSON.stringify([page + '/say-batch']) && since(sent) === 1);
  t('P25: after Send all the cards and the counts are drawn again', await p.evaluate(() =>
    document.getElementById('p-P4').classList.contains('is-receipt') && /drop asked/.test(document.getElementById('piece-P2').textContent)
    && !document.querySelector('.tray-line') && !document.querySelector('.live-state')));
  rewind(sent);
  // R1: an item added while a batch is out stays in the tray when the batch lands; only what was sent leaves it
  await p.goto(base + page);
  const heldBatch = {};
  const arrived = new Promise(go => { heldBatch.arrived = go; });
  await p.route('**/say-batch', route => { heldBatch.route = route; heldBatch.arrived(); });
  await p.locator('#piece-P2 .drop-fold > summary').click();
  await p.locator('#piece-P2 button.a-drop').click();
  sent = mark();
  await p.locator('.tray-bar .a-validate').click();
  await arrived;
  await p.locator('#q-O1 .ask-about > details > summary').click();
  await p.fill('#say-O1-ask', 'added while sending');
  await p.locator('#q-O1 .ask-about button[type="submit"]').click();
  t('R1: an item added while the batch is out joins the tray, the bar still saying Sending', await p.evaluate(() =>
    document.querySelector('.tray-bar h2').textContent === '2 in the tray'
    && /^Sending/.test(document.querySelector('.tray-says').textContent)));
  await heldBatch.route.continue();
  await p.waitForFunction(() => document.querySelector('.tray-bar h2')?.textContent === '1 in the tray');
  const kept = await trayed();
  t('R1: when the batch lands only what was sent leaves: the added item is still in the tray and on its card',
    JSON.stringify(kept.items) === JSON.stringify([['O1', 'comment', 'added while sending']])
    && JSON.stringify(kept.cards) === JSON.stringify(['q-O1 Comment in the tray']) && since(sent) === 1
    && /drop asked/.test(await p.textContent('#piece-P2')));
  await p.unroute('**/say-batch');
  await p.locator('.tray-bar .a-untray').click();
  rewind(sent);
  posts.length = 1; // the P25 checks after this block read the first Send all's post and what follows
  // an item whose card is gone is said, and blocks Send all until removed
  await p.evaluate(() => localStorage.setItem('tray:' + location.pathname.split('/')[2], JSON.stringify(
    [{id: 'x1', ref: 'O9', kind: 'comment', card: 'q-O9', form: 0, fields: {ref: 'O9', comment: '1', text: 'gone'}}])));
  await p.reload();
  t('P25: an item whose card is gone says so and is not sent until removed', await p.evaluate(() => {
    const li = document.querySelector('.tray-bar .tray-items > li');
    return li.classList.contains('is-gone') && li.querySelector('.tray-text').textContent === 'no longer on the page'
      && document.querySelector('.tray-bar .a-validate').disabled;
  }));
  await p.locator('.tray-bar .a-untray').click();
  t('P25: removed, the tray is gone', await p.locator('.tray-bar').count() === 0);
  await p.evaluate(() => { document.querySelector('.ledger-head .ledger-details').open = true; });
  await p.uncheck('#batch-mode');
  await p.locator('#p-P4 button[name="word"][value="commit"]').click();
  await p.waitForSelector('#p-P4.is-collapsed');
  t('P25: batch mode off sends a word at once, as before', JSON.stringify(posts.slice(1)) === JSON.stringify([page + '/say'])
    && await p.locator('.tray-bar').count() === 0);
  p.off('request', count);
  rewind(sent);
  // R2: a send with no answer is not posted again by itself: the card says Delivery unconfirmed and keeps the
  // draft; Check finds a send that landed, or turns into Retry, which posts once
  const sayPosts = [];
  const countSay = r => { if (r.method() === 'POST' && /\/say$/.test(r.url())) sayPosts.push(r.url()); };
  p.on('request', countSay);
  const cardSays = () => p.evaluate(() => {
    const n = document.querySelector('#p-P4 .send-unconfirmed');
    return n ? {text: n.textContent, button: n.querySelector('button').textContent, collapsed: document.getElementById('p-P4').classList.contains('is-collapsed')} : null;
  });
  await p.goto(base + page);
  sent = mark();
  // the request goes out and the server files it; the page gets a network error instead of the answer
  await p.evaluate(() => {
    const real = window.fetch;
    window.fetch = async (...args) => {
      const answer = await real(...args);
      if (/\/say$/.test(String(args[0]))) throw new TypeError('NetworkError: the answer was lost');
      return answer;
    };
  });
  await p.locator('#p-P4 button[name="word"][value="commit"]').click();
  await p.waitForSelector('#p-P4 .send-unconfirmed');
  await p.waitForTimeout(1500);
  const lost = await cardSays();
  t('R2: an answer lost after the server took the send is not posted again, the card says Delivery unconfirmed',
    sayPosts.length === 1 && /^Delivery unconfirmed/.test(lost.text) && lost.button === 'Check' && !lost.collapsed && since(sent) === 1);
  await p.locator('#p-P4 .send-unconfirmed button').click();
  await p.waitForSelector('#p-P4.is-collapsed');
  t('R2: Check finds the send landed and shows the card as sent, with no second post',
    sayPosts.length === 1 && await p.evaluate(() => !document.querySelector('#p-P4 .send-unconfirmed') && document.getElementById('p-P4').classList.contains('is-receipt')));
  rewind(sent);
  sayPosts.length = 0;
  await p.goto(base + page);
  await p.route('**/say', route => route.abort());
  await p.locator('#p-P4 button[name="word"][value="commit"]').click();
  await p.waitForSelector('#p-P4 .send-unconfirmed');
  await p.locator('#p-P4 .send-unconfirmed button').click();
  await p.waitForFunction(() => document.querySelector('#p-P4 .send-unconfirmed button')?.textContent === 'Retry');
  t('R2: a send that did not land is said so, the button becomes Retry, nothing is posted by Check',
    sayPosts.length === 1 && /^Not delivered/.test((await cardSays()).text));
  await p.unroute('**/say');
  await p.locator('#p-P4 .send-unconfirmed button').click();
  await p.waitForSelector('#p-P4.is-collapsed');
  t('R2: Retry posts once and the send lands', sayPosts.length === 2 && since(sent) === 1);
  p.off('request', countSay);
  rewind(sent);
  // P66: an id link carries its item's title in the viewer's tip, shown on hover and on focus; a link to an id
  // not in the ledger has none; a link that says more than the id has none
  for (const [w, h] of [[1300, 900], [412, 900]]) {
    await p.setViewportSize({width: w, height: h});
    await p.goto(base + page);
    const ids = await p.evaluate(() => {
      const tipOf = a => { const d = a.getAttribute('aria-describedby'), e = d && document.getElementById(d);
        return e && e.classList.contains('tip') ? e.textContent : ''; };
      const f = s => [...document.querySelectorAll(s)].filter(a => /^[A-Z]\d+$/.test(a.textContent.trim()));
      const after = f('a[href^="#piece-"]').find(a => /waits for|after/.test(a.parentElement.textContent));
      const forD = f('a[href^="#crit-"]').find(a => /serves|for/.test(a.parentElement.textContent));
      const gone = f('a[href="#piece-P99"]')[0];
      const side = [...document.querySelectorAll('.question-nav li.is-piece a')];
      return {after: after && tipOf(after), forD: forD && tipOf(forD), gone: gone ? tipOf(gone) : null,
              side: side.length > 0 && side.every(a => !a.getAttribute('aria-describedby')),
              title: !!document.querySelector('a[href="#piece-P1"][aria-describedby]')};
    });
    t('P66 ' + w + ': an "after P<n>" (waits for) link carries its piece\'s title', /\S/.test(ids.after || '') && /^[a-z]/.test(ids.after));
    t('P66 ' + w + ': a "serves D<n>" link carries its criterion\'s title', /\S/.test(ids.forD || ''));
    t('P66 ' + w + ': a link to an id not in the ledger has no tip', ids.gone === '');
    t('P66 ' + w + ': a side-list link that shows its title has no tip', ids.side);
    const link = p.locator('a[href="#piece-P2"][aria-describedby]').first();
    const tid = await link.getAttribute('aria-describedby');
    await link.scrollIntoViewIfNeeded();
    await link.hover();
    t('P66 ' + w + ': the tip shows on hover', await p.evaluate(i => getComputedStyle(document.getElementById(i)).display !== 'none', tid));
    await p.mouse.move(0, 0);
    t('P66 ' + w + ': the tip is hidden again', await p.evaluate(i => getComputedStyle(document.getElementById(i)).display === 'none', tid));
    await link.focus();
    await p.keyboard.press('Shift+Tab');
    await p.keyboard.press('Tab');
    t('P66 ' + w + ': the tip shows on keyboard focus', await p.evaluate(i => document.activeElement.getAttribute('aria-describedby') === i
      && getComputedStyle(document.getElementById(i)).display !== 'none', tid));
  }
  // P22: a piece's and a question's card carry their RAID line, an assumption's chip leading to its row in the
  // RAID fold, which lists Risks, Assumptions, Issues and Dependencies; nothing overflows the page; undone after
  run('assume', 'the header fits one line — draw it at 412 px', '--for', 'P2,O1');
  for (const w of [1300, 412]) {
    await p.setViewportSize({width: w, height: 900});
    await p.goto(base + page);
    const r = await p.evaluate(() => {
      const fold = document.querySelector('details.done-fold[id$="-raid"]');
      if (fold) fold.open = true;
      const line = document.querySelector('#piece-P2 .raid');
      // the assumption this check made: an undone one keeps its id, so a
      // run in the second browser gets the next
      const row = [...document.querySelectorAll('[id^="raid-A"]')].find(li => /the header fits one line/.test(li.textContent));
      return {line: !!line && line.getBoundingClientRect().height > 0 && /no risk rated/.test(line.textContent),
              rests: !!row && !!document.querySelector(`#q-O1 .raid a[href="#${row.id}"]`)
                && row.getBoundingClientRect().height > 0,
              lists: fold ? [...fold.querySelectorAll('h3')].map(h => h.textContent.split(' (')[0]).join(', ') : '',
              fits: document.documentElement.scrollWidth <= document.documentElement.clientWidth};
    });
    t('P22 ' + w + ': a piece in flight says its risk is not rated on its RAID line', r.line);
    t('P22 ' + w + ': a question\'s line names its assumption, which leads to its row in the RAID fold', r.rests);
    t('P22 ' + w + ': the RAID fold lists Risks, Assumptions, Issues, Dependencies',
      r.lists === 'Risks, Assumptions, Issues, Dependencies');
    t('P22 ' + w + ': no horizontal overflow with the RAID fold open', r.fits);
  }
  run('undo');
  // P14: a piece's RAID line says which pieces wait on it and which question it prepares, an entry which decision
  // led to it; each link lands on its card or its decision row; undone after
  run('decide', 'start with the header', '--by', 'me', '--led-to', 'P1');
  for (const w of [1300, 412]) {
    await p.setViewportSize({width: w, height: 900});
    await p.goto(base + page);
    const land = async (sel, target) => {
      await p.locator(sel).first().evaluate(a => a.click());
      await p.waitForTimeout(150);
      return p.evaluate(t => location.hash === '#' + t && !!document.getElementById(t)
        && document.getElementById(t).getBoundingClientRect().height > 0, target);
    };
    const said = await p.evaluate(() => ({
      needed: /needed by/.test(document.querySelector('#piece-P1 .ties')?.textContent || ''),
      prepares: /prepares/.test(document.querySelector('#piece-P2 .raid')?.textContent || ''),
      decided: /decided in/.test(document.querySelector('#piece-P1 .raid')?.textContent || ''),
      fits: document.documentElement.scrollWidth <= document.documentElement.clientWidth}));
    t('P14 ' + w + ': P1 says what waits on it, P2 the question it prepares, P1 the decision behind it',
      said.needed && said.prepares && said.decided);
    t('P14 ' + w + ': a "needed by" link lands on the card', await land('#piece-P1 .ties a[href="#piece-P3"]', 'piece-P3'));
    t('P14 ' + w + ': a "prepares" link lands on the question', await land('#piece-P2 .raid a[href="#q-O2"]', 'q-O2'));
    t('P14 ' + w + ': a "decided in" link lands on the decision row',
      await land('#piece-P1 .raid .decided a', await p.evaluate(() => document.querySelector('#piece-P1 .raid .decided a').hash.slice(1))));
    t('P14 ' + w + ': no horizontal overflow', said.fits);
  }
  run('undo');
  // P70: the side list's subtitle is meta text, never drawn as a link
  for (const w of [1300, 412]) {
    await p.setViewportSize({width: w, height: 900});
    await p.goto(base + page);
    const sub = p.locator('.question-nav li.is-piece.is-flight .status').first();
    if (w === 1300) await sub.hover();
    t('P70 ' + w + ': the subtitle is muted, not the accent colour, and not underlined', await p.evaluate(() => {
      const probe = c => { const e = document.createElement('span'); e.style.color = c; document.body.append(e);
        const v = getComputedStyle(e).color; e.remove(); return v; };
      const s = document.querySelector('.question-nav li.is-piece.is-flight .status'), cs = getComputedStyle(s);
      return cs.color === probe('var(--muted)') && cs.color !== probe('var(--accent)') && cs.textDecorationLine === 'none';
    }));
  }
  // N1: the why page leads back: the ledger page's crumbs, and its heading chip lands on the card;
  // P4 has nothing linked either way, which the page says in one line with the way back
  await p.setViewportSize({width: 1300, height: 900});
  await p.goto(base + page + '/why/P4');
  t('N1: the why page has the crumbs All ledgers / the ledger', await p.evaluate(l => {
    const a = [...document.querySelectorAll('.crumbs a')];
    return a.length === 2 && a[0].getAttribute('href') === '/' && a[0].textContent === 'All ledgers' && a[1].getAttribute('href') === l;
  }, page));
  t('N1: an empty why page says so in one line with the way back, no empty helper lines', await p.evaluate(l => {
    const n = document.querySelector('.links-none');
    return !!n && /^Nothing is linked to P4, before or after it\./.test(n.textContent)
      && n.querySelector('a').getAttribute('href') === l + '#piece-P4'
      && !document.querySelector('.links-columns') && !/Each line below/.test(document.body.textContent);
  }, page));
  await Promise.all([p.waitForNavigation(), p.click('#links-title a.id-link')]);
  await p.waitForTimeout(300);
  t('N1: the heading chip lands on the piece\'s card on the ledger page, its fold opened', await p.evaluate(() => {
    const el = document.getElementById('piece-P4'), r = el && el.getBoundingClientRect();
    return location.hash === '#piece-P4' && !!r && el.closest('details').open && r.top >= -1 && r.top < innerHeight;
  }));
  // N2: the evidence a word rests on sits directly above its buttons, with a link to the record's row
  t('N2: the evidence sits directly above the word buttons, linking to its row in the record', await p.evaluate(() => {
    const ev = document.querySelector('#p-P4 > .word-evidence'), f = ev && ev.nextElementSibling;
    const a = ev && ev.querySelector('a[href="#piece-P4"]');
    const buttons = document.querySelector('#p-P4 .word-choices');
    return !!ev && /suite green/.test(ev.textContent) && !!a && /record/.test(a.textContent)
      && f.matches('form.say') && f.contains(buttons) && ev.getBoundingClientRect().bottom <= buttons.getBoundingClientRect().top;
  }));
  // N5: the order as titles with up and down, which rewrite the comma field; the field fits at 390 px
  await p.setViewportSize({width: 390, height: 844});
  await p.goto(base + page);
  await p.evaluate(() => { document.querySelector('details.order-fold').open = true; });
  const order = () => p.evaluate(() => ({
    rows: [...document.querySelectorAll('ol.order-list > li')].map(li => li.dataset.id).join(', '),
    field: document.querySelector('input[name="order"]').value,
    titled: [...document.querySelectorAll('ol.order-list > li')].every(li => li.querySelector('.order-text').textContent.trim().length > 4),
    targets: [...document.querySelectorAll('ol.order-list button')].every(b => { const r = b.getBoundingClientRect(); return r.width >= 44 && r.height >= 44; }),
    fits: (() => { const f = document.querySelector('input[name="order"]'), r = f.getBoundingClientRect();
      return r.right <= f.form.getBoundingClientRect().right + 0.5 && document.documentElement.scrollWidth <= innerWidth; })(),
  }));
  const o1 = await order();
  await p.locator('ol.order-list > li:last-child .a-up').click();
  const o2 = await order();
  await p.locator('ol.order-list > li:first-child .a-down').click();
  const o3 = await order();
  t('N5: the planned pieces are a list of titles, up and down 44 px targets, the field fitting at 390 px',
    o1.rows === o1.field && o1.rows.split(', ').length > 1 && o1.titled && o1.targets && o1.fits);
  t('N5: up and down move a piece and rewrite the comma field', o2.rows === o2.field && o2.field !== o1.field
    && o2.field.split(', ').reverse().join(', ') === o1.field.split(', ').slice(-2).join(', ') && o3.field === o1.field);
  // N3: on a 390 px card the before/after pair stacks, Before over After at the card's width, its caption wrapping
  t('N3: the pair stacks Before over After at the card\'s width at 390 px', await p.evaluate(() => {
    const t = document.querySelector('#p-P4 .mock-tile.is-pair'), s = [...t.querySelectorAll('.side')].map(x => x.getBoundingClientRect());
    const card = t.closest('li').getBoundingClientRect(), cap = t.querySelector('figcaption').getBoundingClientRect();
    return s.length === 2 && Math.abs(s[0].left - s[1].left) < 1 && s[1].top >= s[0].bottom - 1
      && s[0].width > card.width * 0.8 && s[0].right <= card.right && cap.right <= card.right
      && /before/i.test(t.querySelectorAll('.side')[0].textContent + t.querySelectorAll('.side')[0].querySelector('[aria-label]')?.getAttribute('aria-label'));
  }));
  await p.setViewportSize({width: 1300, height: 900});
  await p.waitForTimeout(100);
  t('N3: a wide card keeps the pair side by side', await p.evaluate(() => {
    const s = [...document.querySelectorAll('#p-P4 .mock-tile.is-pair .side')].map(x => x.getBoundingClientRect());
    return s.length === 2 && s[1].left >= s[0].right - 1 && Math.abs(s[0].top - s[1].top) < 1;
  }));
  // N6: a comment written on an option not chosen says so beside it; nothing is blocked
  await p.goto(base + page);
  await p.evaluate(() => { document.querySelectorAll('#q-O1 input[name="choice"]')[0].click(); });
  await p.evaluate(() => { document.querySelectorAll('#q-O1 .choice details')[1].open = true; });
  await p.fill('#q-O1 .choice:nth-of-type(2) textarea', 'about the other one');
  t('N6: writing on an option not chosen shows "this option is not your choice" beside that comment', await p.evaluate(() => {
    const c = document.querySelectorAll('#q-O1 .choice'), w = c[1].querySelector('.comment-unchosen');
    return !!w && /this option is not your choice/i.test(w.textContent) && w.previousElementSibling === c[1].querySelector('textarea')
      && w.getAttribute('role') === 'status' && !c[0].querySelector('.comment-unchosen');
  }));
  await p.evaluate(() => { document.querySelectorAll('#q-O1 input[name="choice"]')[1].click(); });
  t('N6: choosing that option takes the warning away', await p.evaluate(() => !document.querySelector('#q-O1 .comment-unchosen')));
  await p.evaluate(() => { const lid = location.pathname.split('/')[2]; sessionStorage.removeItem('draft:' + lid + ':O1'); });
  // a word sent with text in the comment box carries it: the word buttons say so
  const commitSays = () => p.evaluate(() => document.querySelector('#p-P4 button[name="word"][value="commit"]').innerText.replace(/\s+/g, " ").trim());
  const wordAlone = await commitSays();
  await p.evaluate(() => {
    const ta = document.querySelector('#p-P4 .comment-box textarea');
    ta.closest('details').open = true;
    ta.value = 'see the after picture';
    ta.dispatchEvent(new Event('input', {bubbles: true}));
  });
  const withText = await commitSays();
  await p.evaluate(() => {
    const ta = document.querySelector('#p-P4 .comment-box textarea');
    ta.value = '';
    ta.dispatchEvent(new Event('input', {bubbles: true}));
    ta.closest('details').open = false;
    const lid = location.pathname.split('/')[2];
    sessionStorage.removeItem('draft:' + lid + ':P4');
  });
  t('a word button reads "(with comment)" while the comment box holds text, not otherwise',
    wordAlone === 'Commit' && withText === 'Commit (with comment)' && await commitSays() === 'Commit');
  // N4: batch mode on, each button whose act goes to the tray says so, an answer says it still goes at once,
  // and the tray's button reads Send all with its count
  await p.goto(base + page);
  await p.evaluate(() => { document.querySelector('.ledger-head .ledger-details').open = true; });
  const labels = () => p.evaluate(() => ({
    commit: document.querySelector('#p-P4 button[name="word"][value="commit"]').innerText.trim(),
    comment: document.querySelector('#p-P4 button.a-comment').textContent.trim(),
    drop: document.querySelector('#piece-P2 button.a-drop')?.textContent.trim() || '',
    answer: document.querySelector('#q-O1 > form.say .batch-at-once')?.checkVisibility() || false,
    answerSend: document.querySelector('#q-O1 > form.say > .actions button[type="submit"]').textContent.trim(),
  }));
  const off = await labels();
  await p.check('#batch-mode');
  const on = await labels();
  t('N4: batch mode on, the buttons going to the tray read "… to tray", not before',
    off.commit === 'Commit' && on.commit === 'Commit to tray' && /^Send comment to tray$/.test(on.comment)
    && on.drop === 'Drop P2 to tray' && off.drop === 'Ask to drop P2' && !/to tray/.test(off.comment + off.drop));
  t('N4: the switch says the tray waits until you send them all; no "validate" on the page', await p.evaluate(() =>
    /until you send them all$/.test(document.querySelector('.batch-says').textContent) && !/validat/i.test(document.body.innerText)));
  t('N4: an answer form says its answer is still sent at once, its Send unchanged', on.answer && !off.answer
    && on.answerSend === off.answerSend && await p.evaluate(() =>
      /still sent at once/.test(document.querySelector('#q-O1 > form.say .batch-at-once').textContent)));
  await p.locator('#p-P4 button[name="word"][value="commit"]').click();
  await p.locator('#piece-P2 .drop-fold > summary').click();
  await p.locator('#piece-P2 button.a-drop').click();
  t('N4: the tray\'s button reads "Send all (2)"', await p.evaluate(() =>
    document.querySelector('.tray-bar .a-validate').textContent === 'Send all (2)'));
  await p.locator('.tray-bar .a-untray').first().click();
  t('N4: its count follows the tray: "Send all (1)"', await p.evaluate(() =>
    document.querySelector('.tray-bar .a-validate').textContent === 'Send all (1)'));
  await p.locator('.tray-bar .a-untray').first().click();
  await p.evaluate(() => { document.querySelector('.ledger-head .ledger-details').open = true; });
  await p.uncheck('#batch-mode');
  t('N4: batch mode off, the labels are back', JSON.stringify(await labels()) === JSON.stringify(off));
  // P67: every queue row carries its wait (the journal dates each item), and every title starts at the same x at 1300 px
  await p.setViewportSize({width: 1300, height: 900});
  await p.goto(base + '/');
  t('P67: every queue row has a wait and the titles start at the same x', await p.evaluate(() => {
    const rows = [...document.querySelectorAll('ol.queue > li')];
    const xs = rows.map(r => r.querySelector('.question').getBoundingClientRect().left);
    return rows.length > 1 && rows.every(r => r.querySelector('.wait')) && xs.every(x => Math.abs(x - xs[0]) < 1);
  }));
  // V8: a ledger page watches its own ledger: a write to another ledger
  // moves neither its stamp nor the page, which is not fetched again
  // one per browser: the second browser's run meets the first's ledger, and new refuses to overwrite it
  const other = path.join(path.dirname(ledger), '..', '..', 'shared-other-' + which, '.claude', 'LEDGER.md');
  const runOn = (file, ...words) => execFileSync(path.join(__dirname, '../../bin/ledger'), [words[0], file, ...words.slice(1)],
    {env: process.env, stdio: ['ignore', 'ignore', 'inherit']});
  runOn(other, 'new', '--goal', 'a second ledger for the stamp check', '--title', 'Second ledger',
    '--short', 'a second ledger', '--date', '2026-11-19');
  await p.goto(base + page);
  await p.waitForTimeout(1500);
  const refetched = [];
  const refetch = r => { if (r.resourceType() === 'fetch' && new URL(r.url()).pathname === page) refetched.push(r.url()); };
  p.on('request', refetch);
  const stampWas = await p.evaluate(() => { window.__mark = 1; return document.body.dataset.stamp; });
  runOn(other, 'fact', 'another ledger moved — viewer.cjs');
  await p.waitForTimeout(4500);
  p.off('request', refetch);
  t('V8: a write to another ledger leaves the open ledger page\'s stamp, and the page is not fetched again',
    await p.evaluate(s => window.__mark === 1 && document.body.dataset.stamp === s && !document.querySelector('.live-state'), stampWas)
    && refetched.length === 0);
  // D1 and D3: while a send is out its button says Sending… and is held, the card's other submit
  // buttons wait and the drafts elsewhere stay editable; the head says how many sent entries are
  // unread and that no session is woken while the waker is off, with Switch on beside it
  sent = mark();
  await p.goto(base + page);
  const unreadBefore = await p.evaluate(() => ({count: Number(document.querySelector('.ledger-head > .waker-unread')?.textContent.match(/^\s*(\d+) sent/)?.[1] || 0)}));
  let letGo;
  const gate = new Promise(r => { letGo = r; });
  await p.route('**/say', async route => { await gate; await route.continue(); });
  await p.locator('#p-P4 button[name="word"][value="commit"]').click();
  await p.waitForSelector('#p-P4 button[aria-busy="true"]');
  const inflight = await p.evaluate(() => {
    const subs = [...document.querySelectorAll('#p-P4 form.say button[type="submit"]')];
    const busy = subs.filter(b => b.getAttribute('aria-busy') === 'true');
    const draft = document.querySelector('#q-O1 form.say textarea');
    return {one: busy.length === 1, says: busy[0] && busy[0].textContent.trim(), off: subs.every(b => b.disabled),
            many: subs.length > 1, draft: !!draft && !draft.disabled && !draft.readOnly,
            elsewhere: [...document.querySelectorAll('#q-O1 form.say button[type="submit"]')].every(b => !b.disabled)};
  });
  t('D1: during a held send the pressed button says Sending… and is disabled and aria-busy', inflight.one && inflight.says === 'Sending…' && inflight.off);
  t('D1: during a held send the card\'s other submit buttons are disabled, drafts elsewhere stay editable',
    inflight.many && inflight.off && inflight.draft && inflight.elsewhere);
  letGo();
  await p.waitForSelector('#p-P4.is-collapsed');
  await p.unroute('**/say');
  t('D1: the answer returns every held button (none busy or disabled left on the page)', await p.evaluate(
    () => !document.querySelector('button[aria-busy="true"]') && ![...document.querySelectorAll('form.say button[type="submit"]')].some(b => b.disabled)));
  await p.waitForFunction(n => Number(document.querySelector('.ledger-head .waker-unread')?.textContent.match(/^\s*(\d+) sent/)?.[1]) === n + 1,
    unreadBefore.count, {timeout: 5000}).catch(() => {});
  const unreadLine = () => p.evaluate(() => {
    const n = document.querySelector('.ledger-head > .waker-unread'), b = n && n.querySelector('button'), r = n && n.getBoundingClientRect();
    return n ? {count: Number(n.textContent.match(/^\s*(\d+) sent/)?.[1]), key: n.dataset.key, says: n.querySelector('.waker-says').textContent.trim(),
                button: b.textContent.trim(), on: n.querySelector('input[name="waker"]').value, action: n.getAttribute('action'),
                shown: r.width > 0 && r.height > 0, receiptNote: !!document.querySelector('.waker-note')} : null;
  });
  const unreadAfter = await unreadLine();
  if (!unreadAfter || unreadAfter.count !== unreadBefore.count + 1) console.log('  head line before/after: ' + JSON.stringify([unreadBefore, unreadAfter]));
  t('D3: after a send with the waker off the head says "N+1 sent, not read yet — no session is woken while the waker is off", keyed, with Switch on',
    !!unreadAfter && unreadAfter.count === unreadBefore.count + 1 && unreadAfter.key === 'waker-unread' && unreadAfter.shown
    && unreadAfter.says === unreadAfter.count + ' sent, not read yet — no session is woken while the waker is off'
    && unreadAfter.button === 'Switch on' && unreadAfter.on === 'on' && /^\/l\/[0-9a-f]+\/waker$/.test(unreadAfter.action) && !unreadAfter.receiptNote);
  rewind(sent);
  // the line goes when the waker is switched on, and comes back when it is switched off again
  await p.goto(base + page);
  await p.locator('.ledger-head > .waker-unread button').click();
  await p.waitForSelector('.ledger-head .waker-state.is-on', {state: 'attached'});
  t('D3: with the waker switched on the head line is gone', await p.evaluate(() => !document.querySelector('.waker-unread')));
  await p.evaluate(() => { document.querySelector('.ledger-head details.ledger-details').open = true; });
  await p.locator('.ledger-head .waker button.a-waker').click();
  await p.waitForSelector('.ledger-head .waker-state.is-off', {state: 'attached'});
  t('D3: with the waker switched off again the head line is back', await p.evaluate(() => !!document.querySelector('.ledger-head > .waker-unread')));
  // D4: the last answer of a ledger says nothing is left waiting, politely, takes the focus and keeps
  // "not read by the session yet" visible
  const lone = path.join(path.dirname(ledger), '..', '..', 'shared-lone-' + which, '.claude', 'LEDGER.md');
  runOn(lone, 'new', '--goal', 'a ledger with one question', '--title', 'Lone ledger', '--short', 'one question', '--date', '2026-11-19');
  runOn(lone, 'ask', 'which one?', '--title', 'Only question', '--problem', 'two', '--risk', '3/10 — rework',
    '--choices', 'A = one | B = two', '--recommend', 'A, simple', '--no-picture', 'text only');
  const loneId = require('crypto').createHash('sha1').update(lone).digest('hex').slice(0, 10);
  await p.goto(base + '/l/' + loneId);
  await p.locator('#q-O1 input[name="choice"]').first().check();
  await p.locator('#q-O1 form.say > .actions > button[type="submit"]:not([name])').first().click();
  await p.waitForSelector('#q-O1.is-collapsed');
  await p.waitForFunction(() => document.activeElement && document.activeElement.matches('#q-O1 .next-waiting.is-none'));
  t('D4: the last answer says "Nothing left waiting on you in this ledger", role status, and has the focus', await p.evaluate(() => {
    const n = document.activeElement, tag = document.querySelector('#q-O1 .sent .tag'), r = n.getBoundingClientRect();
    return n.getAttribute('role') === 'status' && n.textContent.trim() === 'Nothing left waiting on you in this ledger' && r.height > 0
      && !!tag && /not read by the session yet/.test(tag.textContent) && tag.getBoundingClientRect().height > 0;
  }));
  // V1 and V2 on a ledger of their own: a piece whose plan gives one word, rated high, and
  // questions rated low and mid
  const shown = path.join(path.dirname(ledger), '..', '..', 'shared-shown-' + which, '.claude', 'LEDGER.md');
  runOn(shown, 'new', '--goal', 'a ledger for the visual checks', '--title', 'Shown ledger', '--short', 'visual checks', '--date', '2026-11-19');
  runOn(shown, 'piece', 'new', '--route', 'sonnet, effort: low', '--title', 'one word', '--problem', 'ready',
    '--risk', '8/10 — it ships', '--plan', 'commit it', '--status', 'verified', '--verified-by', 'me', '--evidence', 'green');
  runOn(shown, 'piece', 'P1', '--awaits', 'commit', '--no-picture', 'no visible change');
  runOn(shown, 'ask', 'low?', '--title', 'Low risk', '--problem', 'two', '--risk', '3/10 — rework',
    '--choices', 'A = one | B = two', '--recommend', 'A, simple', '--no-picture', 'text only');
  runOn(shown, 'ask', 'mid?', '--title', 'Mid risk', '--problem', 'two', '--risk', '6/10 — rework',
    '--choices', 'C = three | D = four', '--recommend', 'C, simple', '--no-picture', 'text only');
  const shownId = require('crypto').createHash('sha1').update(shown).digest('hex').slice(0, 10);
  // the colour a computed value paints, as sRGB bytes: a canvas reads oklch() as well as rgb()
  const meters = () => p.evaluate(() => {
    const g = document.createElement('canvas').getContext('2d', {willReadFrequently: true});
    const rgba = c => { g.clearRect(0, 0, 1, 1); g.fillStyle = c; g.fillRect(0, 0, 1, 1); return [...g.getImageData(0, 0, 1, 1).data]; };
    const rgb = c => rgba(c).slice(0, 3);
    const lum = c => { const [r, gg, b] = c.map(v => { v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; }); return 0.2126 * r + 0.7152 * gg + 0.0722 * b; };
    const ratio = (x, y) => { const [a, b] = [lum(x), lum(y)].sort((m, n) => m - n); return (b + 0.05) / (a + 0.05); };
    const token = n => { const s = document.createElement('span'); s.style.color = `var(--${n})`; document.body.append(s); const c = rgb(getComputedStyle(s).color); s.remove(); return c.join(); };
    return [...document.querySelectorAll('.rating')].map(e => {
      // the first opaque background behind it: every surface of the page is opaque
      let n = e;
      while (n.parentElement && rgba(getComputedStyle(n).backgroundColor)[3] < 255) n = n.parentElement;
      const bg = getComputedStyle(n).backgroundColor;
      const band = (e.closest('.is-low, .is-mid, .is-high').className.match(/is-(low|mid|high)/) || [])[1];
      const ink = rgb(getComputedStyle(e).color).join();
      return {band, text: e.lastChild.textContent, ink, want: token('risk-' + band),
        states: ['ok', 'ask'].map(token), ratio: ratio(rgb(getComputedStyle(e).color), rgb(bg))};
    });
  });
  await p.goto('about:blank');
  await p.setViewportSize({width: 390, height: 844});
  for (const scheme of ['light', 'dark']) {
    await p.emulateMedia({colorScheme: scheme});
    await p.goto(base + '/l/' + shownId);
    await p.evaluate(() => { for (const f of document.querySelectorAll('details.done-fold')) f.open = true; });
    const m = await meters();
    t(`V1 ${scheme}: each meter reads "risk N/10" (work or step on a piece's card) in its band's own risk colour, never a state colour`,
      ['low', 'mid', 'high'].every(b => m.some(x => x.band === b))
      && m.every(x => /^(risk|work|step) \d+\/10$/.test(x.text) && x.ink === x.want && !x.states.includes(x.ink)));
    t(`V1 ${scheme}: every meter's text is at least 4.5:1 on what is behind it (lowest ${Math.min(...m.map(x => x.ratio)).toFixed(2)})`,
      m.every(x => x.ratio >= 4.5));
  }
  await p.emulateMedia({colorScheme: null});
  // a risk's label sits on the baseline of the words after it: a zero-height
  // inline block placed after each lands on its baseline
  const offsets = await p.evaluate(() => {
    const probe = () => { const s = document.createElement('span'); s.style.cssText = 'display:inline-block;width:0;height:0'; return s; };
    return [...document.querySelectorAll('.raid-part.risk')].filter(r => r.querySelector('.rating') && r.lastChild.nodeType === 3).map(r => {
      const a = probe(); r.querySelector('.rating').lastChild.after(a);
      const b = probe(); r.append(b);
      const d = Math.abs(b.getBoundingClientRect().top - a.getBoundingClientRect().top);
      a.remove(); b.remove(); return d;
    });
  });
  t(`a risk's "risk N/10" shares the baseline of its words (largest offset ${Math.max(...offsets).toFixed(1)} px)`,
    offsets.length > 0 && offsets.every(d => d <= 0.5));
  // V2: every waiting card has one filled button, the only word included; here and on the fixture's page
  const primaries = () => p.evaluate(() => [...document.querySelectorAll('li.is-card form.say .word-choices')].map(w => {
    const bs = [...w.querySelectorAll('button')], panel = getComputedStyle(w.closest('li')).backgroundColor;
    return {n: bs.length, filled: bs.filter(b => getComputedStyle(b).backgroundColor !== panel).length};
  }));
  await p.goto(base + '/l/' + shownId);
  const lone1 = await primaries();
  await p.goto(base + page);
  const many = await primaries();
  t('V2: a card offering one word draws it filled, and every waiting card has exactly one filled word',
    lone1.some(x => x.n === 1) && many.some(x => x.n > 1) && [...lone1, ...many].every(x => x.filled === 1));
  // V5: at 390 px a queue row's wait ends its title's line
  await p.goto(base + '/');
  t('V5: at 390 px each queue row\'s wait sits on its title\'s line, after it', await p.evaluate(() => {
    const rows = [...document.querySelectorAll('ol.queue > li')].filter(r => r.querySelector('.wait'));
    return rows.length > 1 && rows.every(r => {
      const w = r.querySelector('.wait').getBoundingClientRect(), ti = r.querySelector('.title').getClientRects()[0];
      return w.left >= ti.right - 0.5 && w.top < ti.bottom && w.bottom > ti.top;
    });
  }));
  await p.goto('about:blank');
  await p.setViewportSize({width: 1300, height: 900});
  // P21: a piece whose picture is being redrawn shows a muted line where its before/after sat
  const redraw = path.join(path.dirname(ledger), '..', '..', 'shared-redraw-' + which, '.claude', 'LEDGER.md');
  const fs = require('fs');
  fs.mkdirSync(path.dirname(redraw), {recursive: true});
  runOn(redraw, 'new', '--goal', 'a ledger for the redraw line', '--title', 'Redraw ledger', '--short', 'redraw line', '--date', '2026-11-19');
  runOn(redraw, 'piece', 'new', '--route', 'sonnet, effort: low', '--title', 'Reorder the list', '--problem', 'not committed',
    '--risk', '2/10 — a reload', '--status', 'verified', '--verified-by', 'me', '--evidence', 'green');
  for (const role of ['before', 'after']) {
    const svg = path.join(path.dirname(redraw), role + '.svg');
    fs.writeFileSync(svg, '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"/>');
    runOn(redraw, 'mockup', svg, '--piece', 'P1', '--' + role);
  }
  runOn(redraw, 'piece', 'P1', '--awaits', 'commit', '--picture-pending', 'the order changed');
  const redrawId = require('crypto').createHash('sha1').update(redraw).digest('hex').slice(0, 10);
  await p.goto(base + '/l/' + redrawId);
  t('P21: a picture being redrawn is a muted line "Picture being redrawn: WHY" on the card, the pair not drawn', await p.evaluate(() => {
    const card = document.querySelector('#p-P1'), line = card && card.querySelector('p.no-picture');
    if (!line) return false;
    const r = line.getBoundingClientRect(), muted = getComputedStyle(line).color, ink = getComputedStyle(card).color;
    return line.textContent === 'Picture being redrawn: the order changed' && r.height > 0 && muted !== ink
      && !card.querySelector('.mock-tile');
  }));
  // a comment sent alone on a piece card leaves its box empty: what was sent is no draft
  await p.goto(base + page);
  const commented = await p.evaluate(() => document.querySelector('li.is-card form.say .comment-box')?.closest('li').id);
  const before = mark();
  await p.evaluate(id => { document.querySelector('#' + id + ' .comment-box').open = true; }, commented);
  await p.fill(`#${commented} .comment-box textarea`, 'a comment alone');
  await p.click(`#${commented} button.a-comment`);
  await p.waitForLoadState("load");
  await p.waitForTimeout(2500);
  t('a comment sent alone leaves its comment box empty, after the page is drawn again', await p.evaluate(id => {
    const ta = document.querySelector('#' + id + ' .comment-box textarea');
    return !!ta && ta.value === '';
  }, commented) && since(before) > 0);
  rewind(before);
  // D2: a question held by a deferred piece says what it waits for, not that it is preparing options;
  // last, because a piece and a question are not taken back; its options name the browser, since two open
  // questions may not offer the same ones and the next browser's checks ask theirs on the same ledger
  run('piece', 'new', '--route', 'sonnet, effort: low', '--title', 'Wait for the API');
  run('piece', 'P5', '--status', 'deferred', '--until', 'the API ships');
  run('ask', 'which client?', '--title', 'Client choice', '--problem', 'two clients', '--risk', '3/10 — rework',
    '--choices', `Web ${which} = w | Native ${which} = n`, '--recommend', `Web ${which}, fine`, '--by', 'P5',
    '--no-picture', 'text only');
  await p.goto(base + page);
  t('D2: a question held by a deferred piece says "Waits for P5, deferred until the API ships"', await p.evaluate(() => {
    const m = [...document.querySelectorAll('li.is-card .meta')].map(x => x.textContent).find(x => /Waits for P5/.test(x)) || '';
    return /Not ready to answer\. Waits for P5, deferred until the API ships\. It moves to Waiting on you when P5 is verified\./.test(m)
      && !/still preparing/.test(m);
  }));
  await p.goto(base + '/favicon.ico').catch(() => {});
  t('no page error and no failed request', errors.length === 0 || (console.log(errors.join('\n')), false));
  await b.close();
  process.exit(fails ? 1 : 0);
})().catch(e => { console.log('FAIL ' + which + ': ' + e.message); process.exit(1); });
