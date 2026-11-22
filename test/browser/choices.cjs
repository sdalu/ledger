// choices.cjs -- the pictures of a question's options in a real browser:
// run by test/browser_run.rb as `node choices.cjs PAGE_URL BROWSER`
// against the ledger of test/support/choices_fixture.rb (O1 with options
// A, B, C; its own picture, and pictures on A and C). Checked at 1280
// and at 390 px: two thumbnails in the tiles of A and C and none in B's,
// the question's own picture reading Before, a click opening the
// picture in the expand pane, equal tile heights in a row. Prints one
// ok/FAIL line per check; exit 1 on any FAIL.
const pw = require(process.env.PLAYWRIGHT_CORE);
const [url, which] = process.argv.slice(2);

(async () => {
  let fails = 0;
  const t = (n, ok, why) => { console.log((ok ? 'ok   ' : 'FAIL ') + which + ': ' + n + (ok || !why ? '' : ' -- ' + why)); if (!ok) fails++; };
  const b = which === 'chrome'
    ? await pw.chromium.launch({executablePath: process.env.CHROME})
    : await pw.firefox.launch({channel: 'moz-firefox', executablePath: process.env.FIREFOX});
  const p = await b.newPage({viewport: {width: 1280, height: 900}});
  await p.goto(url);
  const tiles = () => p.evaluate(() => [...document.querySelectorAll('#q-O1 .choice')].map(c => ({
    option: c.querySelector('label').textContent.trim().split(/\s+/)[0],
    thumbs: c.querySelectorAll('button.a-expand').length,
    rect: c.getBoundingClientRect().toJSON(),
    shot: c.querySelector('button.a-expand')?.getBoundingClientRect().toJSON() ?? null,
    note: c.querySelector('details')?.getBoundingClientRect().toJSON() ?? null,
    label: c.querySelector('label').getBoundingClientRect().toJSON() })));
  const all = await tiles();
  t('three option tiles', all.length === 3, JSON.stringify(all.map(c => c.option)));
  t('two thumbnails, in the tiles of A and C', all.map(c => c.thumbs).join() === '1,0,1', JSON.stringify(all.map(c => [c.option, c.thumbs])));
  t('a thumbnail sits under its text and above its comment fold',
    all.filter(c => c.shot).every(c => c.shot.top >= c.label.bottom - 1 && c.shot.bottom <= c.note.top + 1),
    JSON.stringify(all.map(c => [c.option, c.shot && c.shot.top, c.label.bottom, c.note && c.note.top])));
  const wide = all[0].rect.top === all[1].rect.top;
  t('tiles of a row keep equal heights', !wide || all.every(c => Math.abs(c.rect.height - all[0].rect.height) < 1),
    JSON.stringify(all.map(c => c.rect.height)));
  t('a thumbnail stays inside its tile', all.filter(c => c.shot).every(c => c.shot.left >= c.rect.left - 1 && c.shot.right <= c.rect.right + 1));
  const before = await p.evaluate(() => ({
    label: document.querySelector('#q-O1 .mock-label')?.textContent.trim(),
    own: document.querySelectorAll('#q-O1 .mock-strip:not(.choice *) button.a-expand').length }));
  t('the question\'s own picture reads Before', before.label === 'Before' && before.own === 1, JSON.stringify(before));
  await p.locator('#q-O1 .choice').nth(0).locator('button.a-expand').click();
  t('a click on a thumbnail opens the picture in the pane',
    await p.locator('aside.mock-pane').isVisible()
    && /layout-a\.svg/.test(await p.getAttribute('aside.mock-pane img', 'src') || ''));
  await p.keyboard.press('Escape');
  await p.setViewportSize({width: 390, height: 844});
  const narrow = await tiles();
  t('at 390 px the thumbnails stay inside their tiles and the page does not scroll sideways',
    narrow.filter(c => c.shot).every(c => c.shot.left >= c.rect.left - 1 && c.shot.right <= c.rect.right + 1)
    && await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
    JSON.stringify(narrow.map(c => [c.rect.left, c.rect.right, c.shot && c.shot.right])));
  await b.close();
  process.exit(fails ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
