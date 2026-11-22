// risk.cjs -- Waiting on you sorted and filtered by risk, in a real browser:
// run by test/browser_run.rb as `node risk.cjs PAGE_URL BROWSER` against the
// ledger of test/support/risk_fixture.rb: O1 (risk 8) and the pieces P1 to P7
// rated 3, 9, none, 5, 7, 2, 4: the server's order is read off the page it
// sends (the waits tie to the minute, so no fixed order holds). Prints one ok/FAIL line per check;
// exit 1 on any FAIL.
const pw = require(process.env.PLAYWRIGHT_CORE);
const [url, which] = process.argv.slice(2);

const HIGHEST = ['p-P2', 'q-O1', 'p-P5', 'p-P4', 'p-P7', 'p-P1', 'p-P6', 'p-P3'];

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
  // the cards of Waiting on you in the order the server wrote them
  const sent = await (await p.request.get(url)).text();
  const waiting = sent.slice(sent.indexOf('<section class="waiting"'), sent.indexOf('</section>', sent.indexOf('<section class="waiting"')));
  const OLDEST = [...waiting.matchAll(/<li data-[^>]*? id="([^"]+)"/g)].map(m => m[1]);
  t('the server writes the eight cards', OLDEST.length === 8, OLDEST.join(' '));

  // the cards of Waiting on you as drawn (shown ones only), and the side list's rows, by anchor
  const cards = (shown = true) => p.evaluate(shown => [...document.querySelectorAll('section.waiting > ul.entries > li[id]')]
    .filter(li => !shown || !li.hidden).map(li => li.id), shown);
  const rows = () => p.evaluate(() => {
    const ul = [...document.querySelectorAll('nav.question-nav > ul')].find(u => u.querySelector('li[data-wait-order]'));
    return [...ul.children].filter(li => !li.hidden).map(li => li.querySelector('a').getAttribute('href').slice(1));
  });
  const stored = () => p.evaluate(() => localStorage.getItem('waiting-view'));
  const status = () => p.evaluate(() => document.querySelector('section.waiting > .view-status')?.textContent.trim() || '');
  const badge = () => p.evaluate(() => document.querySelector('section.waiting > h2 .count').textContent.trim());
  const same = (a, c) => JSON.stringify(a) === JSON.stringify(c);
  const choose = label => p.getByRole('radio', {name: label}).check();

  // the defaults: today's order, nothing hidden, the control drawn
  t('the control is shown', await p.locator('.waiting-view').isVisible());
  t('the defaults are Oldest wait and All', await p.getByRole('radio', {name: 'Oldest wait'}).isChecked()
    && await p.getByRole('radio', {name: 'All', exact: true}).isChecked());
  const first = await cards();
  t('by default the cards are in the server order', same(first, OLDEST), first.join(' '));
  t('by default the side list is in the server order', same(await rows(), OLDEST), (await rows()).join(' '));
  t('by default nothing is said hidden', await status() === '', await status());

  // Highest risk: rating descending, ties and the unrated by the server order
  await choose('Highest risk');
  const high = await cards();
  t('Highest risk orders the cards by rating, the unrated last', same(high, HIGHEST), high.join(' '));
  t('Highest risk orders the side list the same way', same(await rows(), HIGHEST), (await rows()).join(' '));

  // Risk 7+ hides what is below it and the unrated, and says how many
  await choose('Risk 7+');
  const top = await cards();
  t('Risk 7+ shows the cards rated 7 or more', same(top, ['p-P2', 'q-O1', 'p-P5']), top.join(' '));
  t('Risk 7+ hides the same rows of the side list', same(await rows(), ['p-P2', 'q-O1', 'p-P5']), (await rows()).join(' '));
  t('Risk 7+ says how many are hidden', await status() === '5 hidden by the risk filter Show all', await status());
  t('the count badge keeps the full count', await badge() === '8', await badge());
  await choose('Risk 4+');
  t('Risk 4+ shows the cards rated 4 or more', same(await cards(), ['p-P2', 'q-O1', 'p-P5', 'p-P4', 'p-P7']), (await cards()).join(' '));
  t('Risk 4+ says 3 are hidden', await status() === '3 hidden by the risk filter Show all', await status());

  // the choice survives a reload
  t('the choice is kept in one key', await stored() === JSON.stringify({order: 'risk', show: '4'}), await stored());
  await p.reload();
  t('the choice survives a reload: order and filter', await p.getByRole('radio', {name: 'Highest risk'}).isChecked()
    && await p.getByRole('radio', {name: 'Risk 4+'}).isChecked());
  t('the choice survives a reload: the cards', same(await cards(), ['p-P2', 'q-O1', 'p-P5', 'p-P4', 'p-P7']), (await cards()).join(' '));

  // Show all, from the status line, sets Show to All
  await p.getByRole('button', {name: 'Show all'}).click();
  t('Show all restores every card', same(await cards(), HIGHEST), (await cards()).join(' '));
  t('Show all sets Show to All', await p.getByRole('radio', {name: 'All', exact: true}).isChecked());
  t('Show all clears the status', await status() === '', await status());
  t('Show all is kept', await stored() === JSON.stringify({order: 'risk', show: 'all'}), await stored());

  // a send in Highest risk goes to the next displayed card, not the server's
  await p.locator('#p-P5 button[name="word"][value="commit"]').click();
  await p.waitForSelector('#p-P5.is-collapsed');
  const landed = await p.waitForFunction(() => document.activeElement.id === 'p-P4', null, {timeout: 5000}).then(() => true, () => false);
  t('after a word on P5 in Highest risk the page goes to P4, the next displayed', landed, await p.evaluate(() => document.activeElement.id));
  t('the receipt stays where P5 was', same(await cards(), HIGHEST), (await cards()).join(' '));
  t('the address names P4', await p.evaluate(() => location.hash) === '#p-P4');
  t('the receipt\'s link names P4', await p.evaluate(() => document.querySelector('#p-P5 a.next-waiting')?.getAttribute('href')) === '#p-P4');

  // with Risk 4+ the last displayed card wraps to the first displayed, skipping what is hidden and what is sent
  await choose('Risk 4+');
  await p.locator('#p-P7 button[name="word"][value="commit"]').click();
  await p.waitForSelector('#p-P7.is-collapsed');
  const wrapped = await p.waitForFunction(() => document.activeElement.id === 'p-P2', null, {timeout: 5000}).then(() => true, () => false);
  t('after a word on the last displayed card the page wraps to the first, P2', wrapped, await p.evaluate(() => document.activeElement.id));
  t('the filter still says what is hidden, the receipts not counted', await status() === '3 hidden by the risk filter Show all', await status());

  // in the defaults the next card is the server's: a page of its own, nothing chosen
  const fresh = await b.newPage({viewport: {width: 1300, height: 1000}});
  await fresh.goto(url);
  const order = await fresh.evaluate(() => [...document.querySelectorAll('section.waiting > ul.entries > li[id]')].map(li => li.id));
  const after = order[order.indexOf('p-P1') + 1] || order[0];
  await fresh.locator('#p-P1 button[name="word"][value="commit"]').click();
  await fresh.waitForSelector('#p-P1.is-collapsed');
  const server = await fresh.evaluate(() => document.querySelector('#p-P1 a.next-waiting')?.getAttribute('href'));
  const plain = await fresh.waitForFunction(id => document.activeElement.id === id, after, {timeout: 5000}).then(() => true, () => false);
  t('with the defaults a word on P1 goes to the card after it in the server order', plain && server === '#' + after, server + ' ' + after);
  t('no script error', errors.length === 0, errors.join('; '));
  await b.close();
  process.exit(fails ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
