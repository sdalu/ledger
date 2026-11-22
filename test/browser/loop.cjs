// loop.cjs -- a question asked by a piece that awaits the user's start, in a
// real browser: run by test/browser_run.rb as `node loop.cjs PAGE_URL BROWSER`
// against the ledger of test/support/loop_fixture.rb: O1 by P1, which awaits
// start, and O2 by P2, which awaits nothing. Prints one ok/FAIL line per
// check; exit 1 on any FAIL.
const pw = require(process.env.PLAYWRIGHT_CORE);
const [url, which] = process.argv.slice(2);

(async () => {
  let fails = 0;
  const t = (n, ok, why) => { console.log((ok ? 'ok   ' : 'FAIL ') + which + ': ' + n + (ok || !why ? '' : ' -- ' + why)); if (!ok) fails++; };
  const b = which === 'chrome'
    ? await pw.chromium.launch({executablePath: process.env.CHROME})
    : await pw.firefox.launch({channel: 'moz-firefox', executablePath: process.env.FIREFOX});
  const p = await b.newPage({viewport: {width: 1300, height: 1000}});
  const errors = [];
  p.on('pageerror', e => errors.push(String(e)));
  await p.goto(url);
  const meta = id => p.evaluate(id => document.querySelector('#' + id + ' .meta')?.textContent.replace(/\s+/g, ' ').trim() || '', id);
  const radios = id => p.evaluate(id => document.querySelectorAll('#' + id + ' form input[type=radio]').length, id);

  const r1 = await radios('q-O1');
  t('O1 shows its picker', r1 >= 2, 'radios ' + r1);
  const m1 = await meta('q-O1');
  t('O1 says P1 waits for your start and can be answered now',
    m1.includes('P1 waits for your start; this question can be answered now') && !/still preparing/.test(m1), m1);
  t('O1 is drawn under Waiting on you',
    await p.evaluate(() => !!document.querySelector('section.waiting #q-O1')));
  const m2 = await meta('q-O2');
  const r2 = await radios('q-O2');
  t('O2 keeps "still preparing" and has no picker',
    /P2 \(planned\) is still preparing/.test(m2) && r2 === 0, m2 + ' radios ' + r2);
  t('no page error', errors.length === 0 || (console.log(errors.join('\n')), false));
  await b.close();
  process.exit(fails ? 1 : 0);
})().catch(e => { console.log('FAIL ' + which + ': ' + e.message); process.exit(1); });
