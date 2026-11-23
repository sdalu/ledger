// live.cjs -- every change made elsewhere drawn in place, in a real
// browser: run by test/browser_run.rb as `node live.cjs PAGE_URL BROWSER
// ADDRESS` against the ledger of test/support/live_fixture.rb (three
// planned pieces, O1 and O2 waiting), which the checks change with
// bin/ledger's words at ADDRESS. Each case sets a marker on window before
// the change and finds it after: the page was never left. Where the change
// moves content, the element at the top of the window stays where it was
// and the focus stays on its element. Prints one ok/FAIL line per check;
// exit 1 on any FAIL.
const pw = require(process.env.PLAYWRIGHT_CORE);
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');
const [url, which, address] = process.argv.slice(2);
const base = new URL(url).origin;
const page = new URL(url).pathname;

(async () => {
  let fails = 0;
  const t = (n, ok, why) => { console.log((ok ? 'ok   ' : 'FAIL ') + which + ': live: ' + n + (ok || !why ? '' : ' -- ' + why)); if (!ok) fails++; };
  // a change made as anyone else makes it: bin/ledger's words against the journal in LEDGER_JOURNAL
  const runAt = (at, word, ...args) => execFileSync(path.join(__dirname, '../../bin/ledger'), [word, at, ...args],
    {env: process.env, stdio: ['ignore', 'ignore', 'inherit']});
  const run = (word, ...args) => runAt(address, word, ...args);
  let touched = 0;
  const touch = () => run('fact', 'live check touch ' + (++touched) + ' — live.cjs');
  const b = which === 'chrome'
    ? await pw.chromium.launch({executablePath: process.env.CHROME})
    : await pw.firefox.launch({channel: 'moz-firefox', executablePath: process.env.FIREFOX});
  // short, so that the sections below the goal are out of the window
  const p = await b.newPage({viewport: {width: 1300, height: 600}});
  const errors = [];
  p.on('pageerror', e => errors.push(String(e)));
  const until = (fn, arg) => p.waitForFunction(fn, arg, {timeout: 8000}).then(() => true, () => false);
  const marked = () => p.evaluate(() => window.__mark === 1);
  const open = async to => {
    await p.goto(to);
    // the stream open, so that a change is pushed at once
    await p.waitForTimeout(1500);
    await p.evaluate(() => { window.__mark = 1; });
  };
  // the element at the top of the window, kept by id, and the focus put
  // on a summary below the change
  const hold = sel => p.evaluate(sel => {
    document.getElementById('flight').scrollIntoView({block: 'start'});
    const f = document.querySelector(sel);
    f.focus({preventScroll: true});
    window.__focus = f;
    return document.getElementById('flight').getBoundingClientRect().top;
  }, sel);
  // [held, why]
  const kept = (top, sel) => p.evaluate(([top, sel]) => {
    const at = document.getElementById('flight').getBoundingClientRect().top;
    const a = document.activeElement;
    return [Math.abs(at - top) <= 1 && a === document.querySelector(sel),
      'top ' + top + ' -> ' + at + ', focus on ' + a.tagName + (a.closest('[id]') ? ' in #' + a.closest('[id]').id : '')];
  }, [top, sel]);
  const FOCUS = '#piece-P3 summary';
  // where a card is, for a check that fails
  const where = id => p.evaluate(id => {
    const c = document.getElementById(id);
    return (c ? 'after #' + c.parentElement.previousElementSibling?.id + ' in ' + c.closest('section, details, div')?.className : 'gone')
      + '; mark ' + window.__mark + '; at ' + location.href + '; status ' + document.querySelector('.live-state')?.dataset.live;
  }, id);

  await open(url);
  // the goal revised: a second goal block drawn above the first
  let top = await hold(FOCUS);
  run('goal', '--quote', 'the page follows every change', '--title', 'Live page, revised',
      '--short', 'every change in place', '--said-in', 'live.cjs');
  let ok = await until(() => document.querySelectorAll('.ledger-main > section.goal').length === 2);
  t('the goal revised elsewhere is drawn in place, no navigation', ok && await marked()
    && await p.evaluate(() => /Live page, revised/.test(document.querySelector('.ledger-main > section.goal').textContent)));
  t('the goal revised: the window does not move and the focus stays', ...await kept(top, FOCUS));

  // the goal done: the first block goes into the fold of done goals
  top = await hold(FOCUS);
  run('goal', 'G1', '--done', 'shown in place');
  ok = await until(() => !!document.querySelector('.ledger-main > details.goal-done section.goal'));
  t('a goal marked done elsewhere moves into Done goals in place, no navigation', ok && await marked()
    && await p.evaluate(() => document.querySelectorAll('.ledger-main > section.goal').length === 1));
  t('the goal done: the window does not move and the focus stays', ...await kept(top, FOCUS));

  // the note: its markup changed in the page fetched (the check rewrites
  // the fetched page, as the server would draw a note of another kind);
  // a note being written is held and says so, Update draws it with the text
  const rewrite = async route => {
    if (route.request().resourceType() !== 'fetch') return route.continue();
    const r = await route.fetch();
    const body = (await r.text()).replace('Leave a note for the session</summary>', 'Leave a note for the session, now or later</summary>');
    return route.fulfill({response: r, body});
  };
  await p.route(base + page, rewrite);
  await p.evaluate(() => { document.querySelector('details.note-fold').open = true; });
  await p.fill('details.note-fold textarea', 'my note, not sent');
  await p.click('h1');
  touch();
  ok = await until(() => !!document.querySelector('details.note-fold .changed-line'));
  t('a note being written, changed elsewhere, is held: its text kept, "Changed since you started" and Update', ok && await marked()
    && await p.evaluate(() => {
      const n = document.querySelector('details.note-fold');
      return n.querySelector('textarea').value === 'my note, not sent' && !/now or later/.test(n.querySelector('summary').textContent)
        && /^Changed since you started/.test(n.querySelector('.changed-line').textContent.trim())
        && !!n.querySelector('.changed-line button.a-take');
    }));
  await p.click('details.note-fold .changed-line button.a-take');
  ok = await until(() => /now or later/.test(document.querySelector('details.note-fold > summary').textContent));
  t('Update draws the note anew in place, keeping the text', ok && await marked() && await p.evaluate(() =>
    document.querySelector('details.note-fold textarea').value === 'my note, not sent'
    && !document.querySelector('details.note-fold .changed-line')));
  await p.fill('details.note-fold textarea', '');
  await p.unroute(base + page, rewrite);

  // the order form: a fourth planned piece joins its list, the fold stays open
  await p.evaluate(() => { document.querySelector('details.order-fold').open = true; });
  top = await hold(FOCUS);
  run('piece', 'new', '--route', 'sonnet, effort: low', '--title', 'the fourth piece',
      '--problem', 'a part of the page', '--risk', '2/10 — a redo');
  ok = await until(() => document.querySelectorAll('details.order-fold ol.order-list > li').length === 4);
  t('the order form drawn anew in place with the new piece, still open, no navigation', ok && await marked()
    && await p.evaluate(() => document.querySelector('details.order-fold').open && !document.querySelector('details.order-fold ol.order-list').hidden
      && !!document.querySelector('#flight + ul #piece-P4')));
  t('the order form: the window does not move and the focus stays', ...await kept(top, FOCUS));

  // a section appearing: a question asked for P2 to prepare opens Being prepared
  top = await hold(FOCUS);
  run('ask', 'which colour?', '--title', 'Colour choice', '--problem', 'two colours', '--risk', '2/10 — a repaint',
      '--choices', 'A = blue | B = green', '--recommend', 'A, calmer', '--by', 'P2', '--no-picture', 'a choice of words');
  ok = await until(() => !!document.querySelector('h2#preparing + ul.entries #q-O3'));
  t('a section coming (Being prepared) is drawn in place with its card, no navigation', ok && await marked());
  t('a section coming: the window does not move and the focus stays', ...await kept(top, FOCUS));

  // a card moving between sections: P2 kept (settled), O3 leaves Being prepared,
  // which empties and goes, for Waiting on you; P2 leaves Unfinished
  top = await hold(FOCUS);
  run('piece', 'P2', '--status', 'kept: settled for the check');
  ok = await until(() => !!document.querySelector('section.waiting #q-O3') && !document.getElementById('preparing'));
  t('a card moving between sections (Being prepared to Waiting on you) is drawn in place, no navigation', ok && await marked()
    && await p.evaluate(() => !document.querySelector('#flight + ul #piece-P2')), await where('q-O3'));
  t('a section emptying (Being prepared) goes in place', ok && await p.evaluate(() =>
    !document.getElementById('preparing') && !document.querySelector('.ledger-main h2#preparing')));
  t('a card moving: the window does not move and the focus stays', ...await kept(top, FOCUS));

  // D2: a send whose answer moves the card or no longer has it: the page
  // is drawn as the answer has it, in place. The check rewrites the page
  // the send comes back with, in the page's own fetch
  const answer = async (id, mode) => {
    await p.evaluate(([id, mode]) => {
      const real = window.fetch;
      window.fetch = async (u, o) => {
        const r = await real(u, o);
        if (!(o && o.method === 'POST' && /\/say$/.test(String(u)))) return r;
        window.fetch = real;
        const doc = new DOMParser().parseFromString(await r.text(), 'text/html');
        const card = doc.getElementById(id);
        if (mode === 'remove') card?.remove();
        else if (card) {
          for (const s of card.querySelectorAll('.sent, .sent-line')) s.remove();
          doc.querySelector('#flight + ul.entries').append(card);
        }
        const html = '<!doctype html>' + doc.documentElement.outerHTML;
        return {ok: r.ok, status: r.status, redirected: r.redirected, url: r.url, text: async () => html};
      };
    }, [id, mode]);
    await p.evaluate(id => { document.querySelector('#' + id + ' input[name="choice"]').click(); }, id);
    await p.click('#' + id + ' > form.say .actions button[type="submit"]:not(.a-comment-only)');
  };
  await open(url);
  await answer('q-O1', 'move');
  ok = await until(() => !!document.querySelector('#flight + ul.entries > #q-O1') && document.activeElement?.id === 'q-O1' && location.hash === '#q-O1');
  t('D2: a send whose answer moves its card draws it where the answer puts it, focused and in view, no navigation', ok && await marked()
    && await p.evaluate(() => {
      const c = document.getElementById('q-O1'), r = c.getBoundingClientRect();
      return document.activeElement === c && r.top >= -1 && r.top < innerHeight && location.hash === '#q-O1'
        && !document.querySelector('section.waiting #q-O1');
    }), await where('q-O1'));
  await answer('q-O2', 'remove');
  ok = await until(() => !document.getElementById('q-O2'));
  t('D2: a send whose answer no longer has its card removes it in place, no navigation', ok && await marked()
    && await p.evaluate(() => !document.querySelector('.live-state')), await where('q-O2'));

  // the links page: its parts drawn in place
  await open(url + '/why/P1');
  t('the links page is a page of parts', await p.evaluate(() => document.body.dataset.page === 'links'));
  run('piece', 'P1', '--title', 'the first piece, renamed');
  ok = await until(() => /renamed/.test(document.querySelector('.links-head').textContent));
  t('the links page changing is drawn in place, no navigation', ok && await marked());

  // signed out: the page says so in place, with a way to sign in; signed
  // in again, the status goes by itself
  const jar = await p.context().cookies();
  if (jar.length) {
    await p.context().clearCookies();
    touch();
    ok = await until(() => document.querySelector('.live-state')?.dataset.live === 'signin');
    t('signed out: a status in place with a Sign in link, no navigation', ok && await marked() && await p.evaluate(() => {
      const l = document.querySelector('.live-state');
      return l.getAttribute('role') === 'status' && l.querySelector('a').getAttribute('href') === '/sign-in'
        && !!l.closest('.receipt') && !l.contains(document.activeElement);
    }));
    await p.context().addCookies(jar);
    touch();
    ok = await until(() => !document.querySelector('.live-state'));
    t('signed in again: the status goes by itself, no navigation', ok && await marked());
  } else console.log('skip ' + which + ': live: signed out (no session: a lan caller)');

  // a new ledger on the index, then that ledger closed while its page is open
  const second = path.join(path.dirname(path.dirname(address)) + '-two', '.claude', 'LEDGER.md');
  const lid2 = crypto.createHash('sha1').update(second).digest('hex').slice(0, 10);
  await open(base + '/');
  const rowsWas = await p.evaluate(() => document.querySelectorAll('section.ledgers tbody th a').length);
  runAt(second, 'new', '--goal', 'a second live ledger', '--title', 'Second live', '--short', 'a second ledger', '--date', '2026-11-19');
  ok = await until(lid => !!document.querySelector('section.ledgers tbody a[href="/l/' + lid + '"]'), lid2);
  t('a new ledger on the index is drawn in place as a row, no navigation', ok && await marked()
    && await p.evaluate(n => document.querySelectorAll('section.ledgers tbody th a').length === n + 1, rowsWas));
  await open(base + '/l/' + lid2);
  runAt(second, 'close', '--abandon');
  ok = await until(() => document.querySelector('.live-state')?.dataset.live === 'closed');
  t('the ledger closed while its page is open: the page stays, a status in place links to the index', ok && await marked()
    && await p.evaluate(() => {
      const l = document.querySelector('.live-state');
      return !!document.querySelector('header.ledger-head') && l.getAttribute('role') === 'status'
        && l.querySelector('a').getAttribute('href') === '/' && !l.contains(document.activeElement);
    }));

  t('no page error', errors.length === 0, errors.join('; '));
  await b.close();
  process.exit(fails ? 1 : 0);
})().catch(e => { console.log('FAIL ' + which + ': live: ' + e.message); process.exit(1); });
