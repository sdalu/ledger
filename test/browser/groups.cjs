// groups.cjs -- the group buttons in a real browser: run by
// test/browser_run.rb as `node groups.cjs PAGE_URL BROWSER` against the
// six pieces of test/support/groups_fixture.rb (P1 to P3 await commit and
// merge, P4 to P6 their start). Both groups show a form, and the click on
// one sends its word to each piece of that group only. Prints one ok/FAIL
// line per check; exit 1 on any FAIL.
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
  const forms = () => p.evaluate(() => [...document.querySelectorAll('section.waiting form.give-all')].map(f => ({
    visible: f.checkVisibility() && f.getBoundingClientRect().height > 0,
    button: f.querySelector('button').textContent.trim(), line: f.querySelector('.give-all-refs').textContent.trim(),
    refs: f.querySelector('[name=refs]').value })));
  const before = await forms();
  t('two group forms are visible', before.length === 2 && before.every(f => f.visible), JSON.stringify(before));
  t('each names its words and its pieces', before.length === 2 && /^Commit \+ Merge all 3$/.test(before[0].button)
    && before[0].line === 'P1–P3' && /^Start all 3$/.test(before[1].button) && before[1].line === 'P4–P6',
    JSON.stringify(before));
  const waiting = () => p.evaluate(() => [...document.querySelectorAll('section.waiting .entries > li[id]')].map(l => l.id.replace(/^p-/, '')));
  t('six pieces wait', (await waiting()).length === 6);
  // a word sent on P1's card: group A's form is drawn again without a reload, group B's is the same element
  await p.evaluate(() => { document.querySelectorAll('form.give-all')[1].mark = 'b'; window.noReload = true; });
  await p.locator('#p-P1 button[name="word"][value="commit"]').click();
  await p.waitForSelector('#p-P1.is-collapsed');
  await p.waitForFunction(() => document.querySelectorAll('form.give-all')[0]?.querySelector('[name=refs]').value === 'P2 P3', null, {timeout: 5000})
    .catch(() => {});
  const after = await p.evaluate(() => ({ noReload: window.noReload === true,
    refs: [...document.querySelectorAll('form.give-all')].map(f => f.querySelector('[name=refs]').value),
    first: document.querySelector('form.give-all .give-all-refs')?.textContent.trim(),
    button: document.querySelector('form.give-all button')?.textContent.trim(),
    marked: document.querySelectorAll('form.give-all')[1]?.mark }));
  t('a word on one card redraws its group form, not the other, without a reload',
    after.noReload && after.refs.join('|') === 'P2 P3|P4 P5 P6' && /^Commit \+ Merge all 2$/.test(after.button) && after.marked === 'b',
    JSON.stringify(after));
  await Promise.all([p.waitForNavigation(), p.locator('form.give-all').nth(1).locator('button').click()]);
  const left = await waiting();
  t('the click sent a word to each piece of its group only', ['P2', 'P3'].every(id => left.includes(id))
    && ['P1', 'P4', 'P5', 'P6'].every(id => !left.includes(id)), JSON.stringify(left));
  await b.close();
  process.exit(fails ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
