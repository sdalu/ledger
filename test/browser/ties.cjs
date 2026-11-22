// ties.cjs -- a piece's ties line in a real browser: run by
// test/browser_run.rb as `node ties.cjs PAGE_URL BROWSER` against the ledger
// of test/support/ties_fixture.rb (P1 waits for P2, P3 is obsolete and
// replaced by P4, P5 builds the open question O1, P6 awaits a word, P7 waits
// for P5 and P6, P8 builds the answered O2, P9 is verified, P10 waits for it).
// Checks that each card's
// line holds the right chips, that a chip's tooltip shows on hover and that
// a click lands on the target card. Prints one ok/FAIL line per check; exit
// 1 on any FAIL.
const pw = require(process.env.PLAYWRIGHT_CORE);
const [url, which] = process.argv.slice(2);

(async () => {
  let fails = 0;
  const t = (n, ok, why) => { console.log((ok ? 'ok   ' : 'FAIL ') + which + ': ' + n + (ok || !why ? '' : ' -- ' + why)); if (!ok) fails++; };
  const b = which === 'chrome'
    ? await pw.chromium.launch({executablePath: process.env.CHROME})
    : await pw.firefox.launch({channel: 'moz-firefox', executablePath: process.env.FIREFOX});
  const p = await b.newPage({viewport: {width: 1280, height: 900}});
  const errors = [];
  p.on('pageerror', e => errors.push(String(e)));
  await p.goto(url);

  // the line of the card or row with ID: [[label, [chip hrefs]]], whatever
  // fold holds it is opened first
  const line = async id => {
    await p.evaluate(id => {
      for (let e = document.getElementById(id); e; e = e.parentElement) if (e.tagName === 'DETAILS') e.open = true;
      document.querySelector('#' + id + ' details.piece-row')?.setAttribute('open', '');
    }, id);
    return p.evaluate(id => [...document.querySelectorAll('#' + id + ' .ties .tie')].map(tie =>
      [tie.querySelector('.tie-label').textContent.trim(), [...tie.querySelectorAll('a.id-link')].map(a => a.getAttribute('href'))]), id);
  };
  const same = (a, c) => JSON.stringify(a) === JSON.stringify(c);

  const p1 = await line('piece-P1');
  t('P1 waits for P2', same(p1, [['waits for', ['#piece-P2']]]), JSON.stringify(p1));
  const p2 = await line('piece-P2');
  t('P2 is needed by P1', same(p2, [['needed by', ['#piece-P1']]]), JSON.stringify(p2));
  const p3 = await line('piece-P3');
  t('P3 is obsoleted by P4', same(p3, [['obsoleted by', ['#piece-P4']]]), JSON.stringify(p3));
  const p4 = await line('piece-P4');
  t('P4 obsoletes P3', same(p4, [['obsoletes', ['#piece-P3']]]), JSON.stringify(p4));
  const p5 = await line('q-O1');
  t('P5 is needed by P7 and builds O1', same(p5, [['needed by', ['#piece-P7']], ['builds', ['#q-O1']]]), JSON.stringify(p5));
  const p7 = await line('piece-P7');
  t('P7 waits for P5 (the question it builds) and P6 (its word card)', same(p7, [['waits for', ['#q-O1', '#p-P6']]]), JSON.stringify(p7));
  const p10 = await line('piece-P10');
  t('P10 waits for the settled P9', same(p10, [['waits for', ['#piece-P9']]]), JSON.stringify(p10));
  const ready = await p.evaluate(() => document.querySelector('#piece-P10 .ties').firstElementChild.textContent.trim());
  t('P10 is ready, P7 is not', ready === 'ready —' && !(await p.evaluate(() => document.querySelector('#piece-P7 .tie-ready'))), ready);
  const states = await p.evaluate(() => {
    const tip = a => document.getElementById(a.getAttribute('aria-describedby')).textContent;
    const a9 = document.querySelector('#piece-P10 .ties a.id-link'), a7 = document.querySelector('#piece-P7 .ties a.id-link');
    return {done: a9.classList.contains('is-done'), tick: a9.textContent.includes('✓'), tip9: tip(a9), plain: !a7.classList.contains('is-done'), tip7: tip(a7)};
  });
  t('a settled wait is muted, ticked and says settled; an unsettled one says its status',
    states.done && states.tick && /settled$/.test(states.tip9) && states.plain && /awaiting|planned/.test(states.tip7), JSON.stringify(states));
  const p8 = await line('p-P8');
  t('P8 builds the answered O2, linked to its decision', p8.length === 1 && p8[0][0] === 'builds' && /^#dec-\d+$/.test(p8[0][1][0]), JSON.stringify(p8));
  const head = await p.evaluate(() => [...document.querySelectorAll('#piece-P3 .succ a.id-link')].map(a => a.getAttribute('href')));
  t('the obsolete row carries its successor in its head', same(head, ['#piece-P4']), JSON.stringify(head));

  // a chip's tooltip shows on hover
  const chip = p.locator('#piece-P1 .ties a.id-link').first();
  await chip.scrollIntoViewIfNeeded();
  await chip.hover();
  const tip = p.locator('#piece-P1 .ties a.id-link + .tip').first();
  t('hovering a chip shows its piece\'s title', await tip.isVisible() && /write the tables/.test(await tip.textContent()),
    await tip.textContent());

  // a click lands on the target card
  const lands = async (from, href) => {
    await p.locator('#' + from + ' .ties a.id-link[href="' + href + '"]').first().click();
    return p.evaluate(h => { const e = document.getElementById(h.slice(1)); const r = e && e.getBoundingClientRect();
      return location.hash === h && !!r && r.bottom > 0 && r.top < innerHeight; }, href);
  };
  t('a click lands on the target card', await lands('piece-P1', '#piece-P2'));
  t('a chip to a piece waiting on you lands on its word card', await lands('piece-P7', '#p-P6'));
  t('a chip to a piece building an open question lands on the question card', await lands('piece-P7', '#q-O1'));
  t('the answered question\'s link lands on its decision', await lands('p-P8', p8[0][1][0]));
  t('no page error', errors.length === 0, errors.join(' | '));
  await b.close();
  process.exit(fails ? 1 : 0);
})().catch(e => { console.log('FAIL ' + which + ': ' + e.message); process.exit(1); });
