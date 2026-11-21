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
  // a mockup placed as a directory is drawn by its index.html in a tile;
  // its page and the image it loads are fetched by that tile's frame,
  // asserted from outside (the frame is an opaque origin)
  errors.length = 0;
  const deckResponses = [];
  p.on('response', r => {
    if (r.url().includes('/deck/')) deckResponses.push({url: r.url(), status: r.status(), frame: r.frame()});
  });
  await p.setViewportSize({width: 1300, height: 900});
  await p.goto(base + pages[0]);
  const deck = p.locator('iframe[src$="/deck/index.html"]');
  t('a directory mockup is drawn in a tile', await deck.count() === 1);
  if (await deck.count() === 1) {
    await deck.scrollIntoViewIfNeeded();
    const frame = await (await deck.elementHandle()).contentFrame();
    const fetched = (name) => deckResponses.find(r => r.url.endsWith('/deck/' + name) && r.frame === frame);
    for (let i = 0; i < 50 && !(fetched('index.html') && fetched('logo.svg')); i++) {
      await new Promise(r => setTimeout(r, 100));
    }
    const box = await deck.boundingBox();
    t('the tile\'s frame loads the directory\'s index.html', fetched('index.html')?.status === 200, JSON.stringify(deckResponses.map(r => r.status + ' ' + r.url)));
    t('the tile\'s frame loads the directory\'s image', fetched('logo.svg')?.status === 200, JSON.stringify(deckResponses.map(r => r.status + ' ' + r.url)));
    t('the tile\'s frame has a size', !!box && box.width > 0 && box.height > 0, JSON.stringify(box));
    t('no refused request for the directory', errors.length === 0, errors.join('; '));
  }
  await b.close();
  process.exit(fails ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
