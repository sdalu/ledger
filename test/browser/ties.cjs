// ties.cjs -- a piece's ties line in a real browser: run by
// test/browser_run.rb as `node ties.cjs PAGE_URL BROWSER` against the ledger
// of test/support/ties_fixture.rb (P1 waits for P2, P3 is obsolete and
// replaced by P4, P5 builds the open question O1). Checks that each card's
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
  t('P5 builds O1', same(p5, [['builds', ['#q-O1']]]), JSON.stringify(p5));
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
  await chip.click();
  const landed = await p.evaluate(() => location.hash);
  const box = await p.evaluate(() => { const r = document.getElementById('piece-P2').getBoundingClientRect(); return r.bottom > 0 && r.top < innerHeight; });
  t('a click lands on the target card', landed === '#piece-P2' && box, landed);
  t('no page error', errors.length === 0, errors.join(' | '));
  await b.close();
  process.exit(fails ? 1 : 0);
})().catch(e => { console.log('FAIL ' + which + ': ' + e.message); process.exit(1); });
