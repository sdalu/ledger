// browser_pages.cjs -- every live ledger's page of a running viewer, in one
// browser: run by test/browser_run.rb as `node browser_pages.cjs BASE
// BROWSER`, BROWSER chrome or firefox, PLAYWRIGHT_CORE the library (the
// signed-in shim). Each page loads with no script error and no refused
// request, holds no horizontal scroll at 1300 and 390 pixels, and every
// picture it names is served. Prints one ok/FAIL line per check; exit 1
// on any FAIL.
const pw = require(process.env.PLAYWRIGHT_CORE);
const [base, which] = process.argv.slice(2);

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
  const errors = [];
  p.on('pageerror', e => errors.push(String(e)));
  p.on('response', r => { if (r.status() >= 400) errors.push(r.status() + ' ' + r.url()); });

  await p.goto(base + '/');
  const pages = await p.evaluate(() =>
    [...document.querySelectorAll('section.ledgers th a[href^="/l/"]')].map(a => a.getAttribute('href')));
  t('the index lists the ledgers', pages.length > 0);
  for (const page of pages) {
    for (const width of [1300, 390]) {
      errors.length = 0;
      await p.setViewportSize({width, height: 900});
      await p.goto(base + page);
      const wide = await p.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
      t(page + ' at ' + width + 'px: no horizontal scroll', wide <= 0, wide + 'px');
      t(page + ' at ' + width + 'px: no error, no refused request', errors.length === 0, errors.join('; '));
    }
    const pictures = await p.evaluate(() =>
      [...new Set([...document.querySelectorAll('[data-src^="/m/"], a[href^="/m/"]')]
        .map(e => e.getAttribute('data-src') || e.getAttribute('href')))]);
    for (const url of pictures) {
      const r = await p.request.get(base + url);
      t(url + ' is served', r.status() === 200, String(r.status()));
    }
  }
  await b.close();
  process.exit(fails ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
