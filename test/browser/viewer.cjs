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
  let touched = 0;
  const touch = () => run('fact', 'browser check touch ' + (++touched) + ' — viewer.cjs');
  const b = which === 'chrome'
    ? await pw.chromium.launch({executablePath: process.env.CHROME})
    : await pw.firefox.launch({channel: 'moz-firefox', executablePath: process.env.FIREFOX});
  const p = await b.newPage({viewport: {width: 1300, height: 900}});
  const errors = [];
  p.on('pageerror', e => errors.push(String(e)));
  p.on('response', r => { if (r.status() >= 400) errors.push(r.status() + ' ' + r.url()); });

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
    quoteOff: [...document.querySelectorAll('button.a-quote')].every(x => !x.hidden && x.disabled),
    figure: !!document.querySelector('#q-O1 pre.figure-text'),
  }));
  t('shadows render (light-dark holds colours only)', s.shadow !== 'none');
  t('Markdown lists keep their bullets', s.bullets === 'disc');
  t('the next step names O1', /^Answer O1:/.test(s.next));
  // O1 to answer and P4's commit, deploy to give; O3 answered and sent
  t('an answered question is the session\'s turn', s.sent && s.waiting === '2');
  t('id and title one card head', s.head);
  t('text figure drawn in the card', s.figure);
  t('quote disabled until a selection', s.quoteOff);
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

  // a draft changed and left holds the reload, and says the ledger changed
  await p.evaluate(() => { document.querySelector('details.order-fold').open = true; });
  await p.fill('input[name="order"]', 'P3, P1');
  await p.click('h1');
  await p.evaluate(() => { window.__mark = 1; });
  touch();
  await p.waitForTimeout(4500);
  t('a draft survives a ledger change', await p.evaluate(() => window.__mark === 1
    && document.querySelector('input[name="order"]').value === 'P3, P1'));
  t('"Ledger changed" is said', await p.locator('.stale-note').isVisible());
  // V6: a ledger page being read never reloads by itself: it says so, and
  // Refresh brings the reader back to the same place
  await p.goto(base + page);
  await p.evaluate(() => { window.__mark = 1; });
  touch();
  await p.waitForTimeout(4500);
  t('V6: a clean ledger page does not reload on a ledger change, and says so', await p.evaluate(() => window.__mark === 1)
    && await p.locator('.stale-note').isVisible());
  t('V6: the note is a polite status reading Ledger changed, button Refresh, no focus taken', await p.evaluate(() => {
    const n = document.querySelector('.stale-note');
    return n.getAttribute('role') === 'status' && /^Ledger changed/.test(n.textContent.trim())
      && n.querySelector('button.a-refresh').textContent.trim() === 'Refresh' && !n.contains(document.activeElement);
  }));
  const reach = await p.evaluate(() => { scrollTo(0, 400); return scrollY; });
  t('V6: the fixture page scrolls far enough to test', reach > 100);
  await Promise.all([p.waitForNavigation(), p.click('.stale-note button.a-refresh')]);
  await p.waitForTimeout(500);
  t('V6: Refresh reloads and keeps the scroll position within 50 px', await p.evaluate(() => window.__mark === undefined)
    && Math.abs(await p.evaluate(() => scrollY) - reach) <= 50);
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
  // R10: what was picked and typed survives the Refresh of the Ledger changed note
  await p.fill('#q-O1 .choice:nth-of-type(2) textarea', 'the second host');
  await p.click('h1');
  touch();
  await p.waitForTimeout(4500);
  await Promise.all([p.waitForNavigation(), p.click('.stale-note button.a-refresh')]);
  await p.waitForTimeout(500);
  t('R10: after Refresh the choice and the comment are back, open, with a line saying so', await p.evaluate(() => {
    const f = document.querySelector('#q-O1 > form.say'), n = f.querySelector('.draft-note');
    return f.querySelectorAll('input[name="choice"]')[1].checked && f.querySelectorAll('.choice textarea')[1].value === 'the second host'
      && f.querySelectorAll('.choice details')[1].open && n && n.getAttribute('role') === 'status'
      && /^Kept from before the refresh: your choice B and your comment, not sent yet\./.test(n.textContent);
  }));
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
  // the index is a queue to glance at: it still reloads quietly
  await p.goto(base + '/');
  t('R5: a neutral id chip in the legend splits in gray: a pale letter, a solid number', await p.evaluate(() => {
    const lg = document.querySelector('#index-legend'); if (!lg) return false;
    const d = lg.closest('details'); if (d) d.open = true;
    const c = lg.querySelector('.tag.is-split'); if (!c) return false;
    const l = getComputedStyle(c.querySelector('.l')).backgroundColor, n = getComputedStyle(c.querySelector('.n')).backgroundColor;
    return l !== n && n !== 'rgba(0, 0, 0, 0)';
  }));
  await p.waitForTimeout(1500);
  await p.evaluate(() => { window.__mark = 1; });
  touch();
  await p.waitForTimeout(4500);
  t('V6: a clean index reloads by itself', await p.evaluate(() => window.__mark === undefined));
  // the stream pushes it: within 3 s, before the 3 s fallback poll could
  await p.goto(base + '/');
  await p.waitForTimeout(1500);
  await p.evaluate(() => { window.__mark = 1; });
  touch();
  await p.waitForTimeout(2500);
  t('a clean index reloads within 3 s while its EventSource is open', await p.evaluate(() => window.__mark === undefined));

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
      && !l.closest('.stale-note') && !document.querySelector('.stale-note') && !l.contains(document.activeElement);
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
  // full screen beside Close, where the browser allows it; the same button leaves it
  if (await p.evaluate(() => document.fullscreenEnabled)) {
    await p.click('aside.mock-pane button.a-full');
    await p.waitForFunction(() => document.fullscreenElement?.matches('aside.mock-pane'), null, { timeout: 5000 }).catch(() => {});
    const on = await p.evaluate(() => [!!document.fullscreenElement?.matches('aside.mock-pane'),
      document.querySelector('aside.mock-pane .a-full span').textContent]);
    await p.click('aside.mock-pane button.a-full');
    await p.waitForFunction(() => !document.fullscreenElement
      && document.querySelector('aside.mock-pane .a-full span').textContent === 'Full screen', null, { timeout: 5000 }).catch(() => {});
    t('full screen beside Close: on, then off', on[0] && on[1] === 'Exit full screen'
      && await p.evaluate(() => !document.fullscreenElement
        && document.querySelector('aside.mock-pane .a-full span').textContent === 'Full screen'));
  }
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
  t('R11: the trash shows its word Close where the card is narrow, and not where it is wide', labelWide === 'none'
    && await p.evaluate(() => { const l = document.querySelector('.drop-fold > summary > .drop-label');
      return getComputedStyle(l).display !== 'none' && l.textContent === 'Close'; }));
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
    return c.classList.contains('is-receipt') && /^You asked: Commit · sent \d\d:\d\d · awaiting filing$/.test(c.querySelector('.sent-line').textContent.trim())
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
  t('P80: the user\'s own send raises no "Ledger changed" note', await p.evaluate(() => !document.querySelector('.stale-note')));
  await p.locator('#p-P4 > details.comment-fold > summary').click();
  await p.waitForSelector('#p-P4:not(.is-collapsed)');
  t('P80: Change opens the card again in place', await p.evaluate(() => {
    const c = document.getElementById('p-P4'), f = c.querySelector('details.comment-fold');
    return !c.classList.contains('is-collapsed') && f.open && f.querySelector('form.say').getBoundingClientRect().height > 20
      && c.getBoundingClientRect().height > 130;
  }) && await idx() === at);
  rewind(sent);
  // a change made by someone else while the send is out still shows the note
  await p.goto(base + page);
  await p.route('**/say', async route => {
    run('ask', '--title', 'Late question', 'anything else?', '--problem', 'asked meanwhile', '--risk', '5/10 — none',
      '--choices', 'A = a | B = b', '--recommend', 'A, fine', '--no-picture', 'text only');
    sent = mark();
    await route.continue();
  });
  await p.locator('#p-P4 button[name="word"][value="commit"]').click();
  await p.waitForSelector('#p-P4.is-collapsed');
  await p.waitForSelector('.stale-note', {timeout: 5000}).catch(() => {});
  t('P80: an outside change made during the send still shows "Ledger changed"', await p.evaluate(() => !!document.querySelector('.stale-note')));
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
    const link = p.locator('a[href="#piece-P1"][aria-describedby]').first();
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
      const line = document.querySelector('#piece-P1 .raid');
      const row = document.getElementById('raid-A1');
      return {line: !!line && line.getBoundingClientRect().height > 0 && /no risk rated/.test(line.textContent),
              rests: !!document.querySelector('#q-O1 .raid a[href="#raid-A1"]') && !!row
                && row.getBoundingClientRect().height > 0,
              lists: fold ? [...fold.querySelectorAll('h3')].map(h => h.textContent.split(' (')[0]).join(', ') : '',
              fits: document.documentElement.scrollWidth <= document.documentElement.clientWidth};
    });
    t('P22 ' + w + ': a piece in flight says its risk is not rated on its RAID line', r.line);
    t('P22 ' + w + ': a question\'s line names A1, which leads to its row in the RAID fold', r.rests);
    t('P22 ' + w + ': the RAID fold lists Risks, Assumptions, Issues, Dependencies',
      r.lists === 'Risks, Assumptions, Issues, Dependencies');
    t('P22 ' + w + ': no horizontal overflow with the RAID fold open', r.fits);
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
  // P67: every queue row carries its wait (the journal dates each item), and every title starts at the same x at 1300 px
  await p.setViewportSize({width: 1300, height: 900});
  await p.goto(base + '/');
  t('P67: every queue row has a wait and the titles start at the same x', await p.evaluate(() => {
    const rows = [...document.querySelectorAll('ol.queue > li')];
    const xs = rows.map(r => r.querySelector('.question').getBoundingClientRect().left);
    return rows.length > 1 && rows.every(r => r.querySelector('.wait')) && xs.every(x => Math.abs(x - xs[0]) < 1);
  }));
  await p.goto(base + '/favicon.ico').catch(() => {});
  t('no page error and no failed request', errors.length === 0 || (console.log(errors.join('\n')), false));
  await b.close();
  process.exit(fails ? 1 : 0);
})().catch(e => { console.log('FAIL ' + which + ': ' + e.message); process.exit(1); });
