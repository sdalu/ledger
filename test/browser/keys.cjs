// keys.cjs -- a quiet page keeps its mockup links valid: run by
// test/browser_run.rb with KEYS=1 as `node keys.cjs BASE BROWSER`, the viewer
// booted with a short $LEDGER_MOCKUP_TTL (seconds, in TTL here). The page
// is opened and left alone past the lifetime of the keys it was drawn
// with; its picture link then carries a fresh key, which opens with no
// session at all, while the old key no longer does. Prints one ok/FAIL
// line per check; exit 1 on any FAIL.
const pw = require(process.env.PLAYWRIGHT_CORE);
const [base, which] = process.argv.slice(2);
const TTL = Number(process.env.LEDGER_MOCKUP_TTL);

(async () => {
  let fails = 0;
  const t = (n, ok, why) => {
    console.log((ok ? 'ok   ' : 'FAIL ') + which + ': ' + n + (ok || !why ? '' : ' -- ' + why));
    if (!ok) fails++;
  };
  const b = which === 'chrome'
    ? await pw.chromium.launch({executablePath: process.env.CHROME})
    : await pw.firefox.launch({channel: 'moz-firefox', executablePath: process.env.FIREFOX});
  const p = await b.newPage({viewport: {width: 1300, height: 900}});
  const link = () => p.evaluate(() => document.querySelector('a[href^="/m/k/"]')?.getAttribute('href') ?? null);
  await p.goto(base + '/');
  const pages = await p.evaluate(() =>
    [...document.querySelectorAll('section.ledgers th a[href^="/l/"]')].map(a => a.getAttribute('href')));
  let before = null;
  for (const page of pages) {
    await p.goto(base + page);
    if ((before = await link())) break;
  }
  t('a ledger page carries a keyed picture link', !!before);
  if (before) {
    // no session: what a frame without one asks with
    const status = async url => (await fetch(base + url)).status;
    t('the key opens the picture at first', await status(before) === 200, String(await status(before)));
    await new Promise(r => setTimeout(r, (TTL + 6) * 1000));
    const after = await link();
    t('the old key has lapsed', await status(before) === 404, String(await status(before)));
    t('the quiet page renewed its link', !!after && after !== before, String(after));
    t('the renewed link opens with no session', !!after && await status(after) === 200, String(after && await status(after)));
  }
  await b.close();
  process.exit(fails ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
