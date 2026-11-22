// meters.cjs -- a word card's step and work meters, in a real browser: run by
// test/browser_run.rb as `node meters.cjs PAGE_URL BROWSER` against the ledger
// of test/support/meters_fixture.rb: P1 dispatched (work 6/10), irreversible,
// awaiting commit and push (step 7 combined, 4 for Commit); P2 kept (work
// 7/10) awaiting deploy (step 5). Prints one ok/FAIL line per check; exit 1 on
// any FAIL.
const pw = require(process.env.PLAYWRIGHT_CORE);
const [url, which] = process.argv.slice(2);

(async () => {
  let fails = 0;
  const t = (n, ok, why) => { console.log((ok ? 'ok   ' : 'FAIL ') + which + ': ' + n + (ok || !why ? '' : ' -- ' + why)); if (!ok) fails++; };
  const b = which === 'chrome'
    ? await pw.chromium.launch({executablePath: process.env.CHROME})
    : await pw.firefox.launch({channel: 'moz-firefox', executablePath: process.env.FIREFOX});
  const p = await b.newPage({viewport: {width: 1280, height: 1000}});
  const errors = [];
  p.on('pageerror', e => errors.push(String(e)));
  // each meter of a card: what it reads, where it is, and its text's contrast
  // on the first opaque background behind it
  const read = id => p.evaluate(id => {
    const g = document.createElement('canvas').getContext('2d', {willReadFrequently: true});
    const rgba = c => { g.clearRect(0, 0, 1, 1); g.fillStyle = c; g.fillRect(0, 0, 1, 1); return [...g.getImageData(0, 0, 1, 1).data]; };
    const lum = c => { const [r, gg, bb] = c.slice(0, 3).map(v => { v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; }); return 0.2126 * r + 0.7152 * gg + 0.0722 * bb; };
    const ratio = (x, y) => { const [a, c] = [lum(x), lum(y)].sort((m, n) => m - n); return (c + 0.05) / (a + 0.05); };
    const card = document.getElementById(id);
    const contrast = e => {
      let n = e;
      while (n.parentElement && rgba(getComputedStyle(n).backgroundColor)[3] < 255) n = n.parentElement;
      return ratio(rgba(getComputedStyle(e).color), rgba(getComputedStyle(n).backgroundColor));
    };
    const steps = [...card.querySelectorAll('.word-choice')].map(w => {
      const button = w.querySelector('button').getBoundingClientRect();
      const meter = w.querySelector('.step .rating');
      const box = meter?.getBoundingClientRect();
      return {word: w.querySelector('button').value, text: meter?.lastChild.textContent,
        label: meter?.getAttribute('aria-label'), visible: !!box && box.width > 0 && box.height > 0,
        under: !!box && box.top >= button.bottom - 0.5 && box.left >= button.left - 0.5 && box.right <= button.right + 0.5,
        ratio: meter ? contrast(meter) : 0};
    });
    const work = card.querySelector('.raid-part.risk .rating');
    return {steps, work: work?.lastChild.textContent, workLabel: work?.getAttribute('aria-label'),
      workRatio: work ? contrast(work) : 0, risk: !!card.querySelector('.raid')?.textContent.match(/risk \d+\/10/)};
  }, id);

  for (const scheme of ['light', 'dark']) {
    await p.emulateMedia({colorScheme: scheme});
    await p.goto(url);
    const one = await read('p-P1');
    const two = await read('p-P2');
    const by = (m, w) => m.steps.find(s => s.word === w) || {};
    t(`${scheme}: P1's combined button reads step 7/10, the highest of its words, irreversible`,
      by(one, 'commit, push').text === 'step 7/10', JSON.stringify(by(one, 'commit, push')));
    t(`${scheme}: P1's Commit reads step 4/10`, by(one, 'commit').text === 'step 4/10', JSON.stringify(by(one, 'commit')));
    t(`${scheme}: P2's Deploy reads step 5/10`, by(two, 'deploy').text === 'step 5/10', JSON.stringify(by(two, 'deploy')));
    t(`${scheme}: each step meter is drawn under its own button, inside its column`,
      [...one.steps, ...two.steps].every(s => s.visible && s.under), JSON.stringify([...one.steps, ...two.steps]));
    t(`${scheme}: a step meter is named for a screen reader`, by(one, 'commit').label === 'step 4 out of 10', by(one, 'commit').label);
    t(`${scheme}: P1's RAID line rates the work from its dispatch, 6/10`, one.work === 'work 6/10' && !one.risk, one.work);
    t(`${scheme}: P2's RAID line rates the work from its own risk, 7/10`, two.work === 'work 7/10' && !two.risk, two.work);
    const ratios = [...one.steps, ...two.steps].map(s => s.ratio).concat([one.workRatio, two.workRatio]);
    t(`${scheme}: every meter's text is at least 4.5:1 on what is behind it (lowest ${Math.min(...ratios).toFixed(2)})`,
      ratios.every(r => r >= 4.5));
  }
  t('no script error', errors.length === 0, errors.join('; '));
  await b.close();
  process.exit(fails ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
