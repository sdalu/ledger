// long.cjs -- a word sent on a long page, in a real browser: run by
// test/browser_run.rb as `node long.cjs PAGE_URL BROWSER` against the
// twelve waiting pieces of test/support/long_fixture.rb, at 390x844.
// The word on the 6th card takes the page to the 7th, the card after the
// one answered, not the first waiting. Prints one ok/FAIL line per check;
// exit 1 on any FAIL.
const pw = require(process.env.PLAYWRIGHT_CORE);
const [url, which] = process.argv.slice(2);

(async () => {
  let fails = 0;
  const t = (n, ok, why) => { console.log((ok ? 'ok   ' : 'FAIL ') + which + ': ' + n + (ok || !why ? '' : ' -- ' + why)); if (!ok) fails++; };
  const b = which === 'chrome'
    ? await pw.chromium.launch({executablePath: process.env.CHROME})
    : await pw.firefox.launch({channel: 'moz-firefox', executablePath: process.env.FIREFOX});
  const p = await b.newPage({viewport: {width: 390, height: 844}});
  await p.goto(url);
  const waiting = await p.evaluate(() => [...document.querySelectorAll('section.waiting .entries > li[id]')].map(l => l.id));
  t('twelve pieces wait on the user', waiting.length >= 12, String(waiting.length));
  const [sixth, seventh] = [waiting[5], waiting[6]];
  await p.evaluate(id => document.getElementById(id).scrollIntoView({block: 'start'}), sixth);
  await p.locator('#' + sixth + ' button[name="word"][value="commit"]').click();
  await p.waitForSelector('#' + sixth + '.is-collapsed');
  const landed = await p.waitForFunction(id => {
    const r = document.getElementById(id).getBoundingClientRect();
    return r.top >= -8 && r.top <= 8;
  }, seventh, {timeout: 5000}).then(() => true, () => false);
  const state = await p.evaluate(id => ({
    top: document.getElementById(id).getBoundingClientRect().top,
    focused: document.activeElement.id, hash: location.hash}), seventh);
  t('a word on the 6th card lands with the 7th card\'s top at the viewport top', landed, JSON.stringify(state));
  t('the 7th card is focused', state.focused === seventh, state.focused);
  t('the 7th card\'s hash is in the address', state.hash === '#' + seventh, state.hash);
  await b.close();
  process.exit(fails ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
