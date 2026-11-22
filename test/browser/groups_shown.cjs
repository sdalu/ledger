// groups_shown.cjs -- the group buttons follow the risk filter, in a real
// browser: run by test/browser_run.rb as `node groups_shown.cjs PAGE_URL
// BROWSER` against the ledger of test/support/groups_fixture.rb (P1 to P3
// await commit and merge, rated 3, 5, 7; P4 to P6 await their start, rated
// 2). With Risk 4+ the first group names, counts and sends P2 and P3 only,
// the second has nothing shown and its form is gone; Show all restores
// both as the server drew them. Prints one ok/FAIL line per check; exit 1
// on any FAIL.
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
    button: f.querySelector('button').textContent.trim(),
    said: f.querySelector('p').textContent.trim(),
    chips: [...f.querySelectorAll('.give-all-refs a.id-link')].map(a => a.textContent.trim()).join(' '),
    tips: f.querySelectorAll('.give-all-refs .tip').length,
    refs: f.querySelector('[name=refs]').value })));
  const show = value => p.evaluate(v => {
    const r = document.querySelector('.waiting-view input[name="view-show"][value="' + v + '"]');
    r.checked = true;
    r.dispatchEvent(new Event('change', {bubbles: true}));
  }, value);
  const all = await forms();
  t('by default both forms name all their pieces',
    all.length === 2 && all.every(f => f.visible) && all[0].refs === 'P1 P2 P3' && all[1].refs === 'P4 P5 P6'
    && /all 3$/.test(all[0].button) && /^3 await/.test(all[0].said), JSON.stringify(all));

  await show('4');
  const some = await forms();
  t('with Risk 4+ a group of three with one hidden reads all 2, its refs and chips the two shown',
    some[0].visible && /^Commit \+ Merge all 2$/.test(some[0].button) && /^2 await/.test(some[0].said)
    && some[0].refs === 'P2 P3' && some[0].chips === 'P2 P3' && some[0].tips === 2, JSON.stringify(some));
  t('a group with no piece shown has no form', !some[1].visible, JSON.stringify(some));

  await show('7');
  const one = await forms();
  t('a group left with one shown piece has no form', !one[0].visible, JSON.stringify(one));

  await show('4');
  await p.reload();
  const kept = await forms();
  t('the filter, remembered, fits the forms after a reload', kept[0].refs === 'P2 P3' && !kept[1].visible, JSON.stringify(kept));

  await p.locator('.view-status .a-show-all').click();
  const back = await forms();
  t('Show all restores the server forms', JSON.stringify(back) === JSON.stringify(all), JSON.stringify(back));

  await show('4');
  await Promise.all([p.waitForNavigation(), p.locator('section.waiting form.give-all').first().locator('button').click()]);
  const left = await p.evaluate(() => [...document.querySelectorAll('section.waiting .entries > li[id]')].map(l => l.id.replace(/^p-/, '')));
  t('the click gave a word to P2 and P3 only', ['P1', 'P4', 'P5', 'P6'].every(id => left.includes(id))
    && ['P2', 'P3'].every(id => !left.includes(id)), JSON.stringify(left));
  await b.close();
  process.exit(fails ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
