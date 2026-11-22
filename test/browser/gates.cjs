// gates.cjs -- a back card's gate chips and folded report, in a real browser:
// run by test/browser_run.rb as `node gates.cjs PAGE_URL BROWSER` against the
// ledger of test/support/gates_fixture.rb: P1 back with rubocop passed, unit
// failed (2 failures in piece_test.rb), browser running, lint queued and the
// report DONE_WITH_CONCERNS; P2 verified, its gate unsaid. Prints one ok/FAIL
// line per check; exit 1 on any FAIL.
const pw = require(process.env.PLAYWRIGHT_CORE);
const [url, which] = process.argv.slice(2);

const CHIPS = ['rubocop passed', 'unit failed', 'browser running', 'lint queued'];
const TOKENS = {passed: 'ok', failed: 'fail', running: 'accent', queued: 'muted'};

(async () => {
  let fails = 0;
  const t = (n, ok, why) => { console.log((ok ? 'ok   ' : 'FAIL ') + which + ': ' + n + (ok || !why ? '' : ' -- ' + why)); if (!ok) fails++; };
  const b = which === 'chrome'
    ? await pw.chromium.launch({executablePath: process.env.CHROME})
    : await pw.firefox.launch({channel: 'moz-firefox', executablePath: process.env.FIREFOX});
  const p = await b.newPage({viewport: {width: 1280, height: 1000}});
  const errors = [];
  p.on('pageerror', e => errors.push(String(e)));
  // each chip: its text, its colour against the token its state names, and
  // its contrast on the first opaque background behind it
  const chips = () => p.evaluate(TOKENS => {
    const g = document.createElement('canvas').getContext('2d', {willReadFrequently: true});
    const rgba = c => { g.clearRect(0, 0, 1, 1); g.fillStyle = c; g.fillRect(0, 0, 1, 1); return [...g.getImageData(0, 0, 1, 1).data]; };
    const lum = c => { const [r, gg, bb] = c.slice(0, 3).map(v => { v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; }); return 0.2126 * r + 0.7152 * gg + 0.0722 * bb; };
    const ratio = (x, y) => { const [a, c] = [lum(x), lum(y)].sort((m, n) => m - n); return (c + 0.05) / (a + 0.05); };
    const token = n => { const s = document.createElement('span'); s.style.color = `var(--${n})`; document.body.append(s); const c = rgba(getComputedStyle(s).color).slice(0, 3).join(); s.remove(); return c; };
    return [...document.querySelectorAll('#piece-P1 ul.gates .gate')].map(e => {
      let n = e;
      while (n.parentElement && rgba(getComputedStyle(n).backgroundColor)[3] < 255) n = n.parentElement;
      const state = e.className.match(/is-(\w+)/)[1];
      return {text: e.textContent, ink: rgba(getComputedStyle(e).color).slice(0, 3).join(), want: token(TOKENS[state]),
        ratio: ratio(rgba(getComputedStyle(e).color), rgba(getComputedStyle(n).backgroundColor))};
    });
  }, TOKENS);
  const tip = () => p.evaluate(() => {
    const box = document.querySelector('#piece-P1 .gate.is-passed + .tip');
    return {shown: getComputedStyle(box).display !== 'none', text: box.textContent};
  });

  for (const scheme of ['light', 'dark']) {
    await p.emulateMedia({colorScheme: scheme});
    await p.goto(url);
    const m = await chips();
    t(`${scheme}: P1's gates are four chips, NAME STATE, in the order recorded`,
      JSON.stringify(m.map(x => x.text)) === JSON.stringify(CHIPS), m.map(x => x.text).join(' | '));
    t(`${scheme}: each chip is drawn in its state's colour (passed ok, failed fail, running accent, queued muted)`,
      m.every(x => x.ink === x.want), JSON.stringify(m));
    t(`${scheme}: every chip's text is at least 4.5:1 on what is behind it (lowest ${Math.min(...m.map(x => x.ratio)).toFixed(2)})`,
      m.every(x => x.ratio >= 4.5));
  }
  await p.emulateMedia({colorScheme: null});
  await p.goto(url);
  t('the time is not shown until asked', !(await tip()).shown);
  await p.hover('#piece-P1 .gate.is-passed');
  const hovered = await tip();
  t('hovering a chip shows its state and time', hovered.shown && /^passed \d{4}-\d\d-\d\d \d\d:\d\d$/.test(hovered.text), JSON.stringify(hovered));
  await p.mouse.move(0, 0);
  await p.focus('#piece-P1 .gate.is-passed');
  await p.keyboard.press('Shift+Tab');
  await p.keyboard.press('Tab');
  t('a chip reached by the keyboard shows its time too', (await tip()).shown);
  const said = await p.evaluate(() => { const n = document.querySelector('#piece-P1 ul.gates').nextElementSibling; return n && n.matches('.gate-failure') ? n.textContent : ''; });
  t('the last failure\'s detail is said right under the chips', said === 'unit: 2 failures in piece_test.rb', said);
  const fold = p.locator('#piece-P1 details.report');
  t('the report is folded', await fold.count() === 1 && !(await fold.evaluate(d => d.open)));
  t('its summary is "Report: DONE_WITH_CONCERNS"', (await fold.locator('summary').textContent()).trim() === 'Report: DONE_WITH_CONCERNS');
  await fold.locator('summary').click();
  const lines = await fold.locator('.report-lines').innerText();
  t('opened, it reads the lines after the status', await fold.locator('.report-lines').isVisible() && lines.includes('- two unit failures remain'), lines);
  const elsewhere = await p.evaluate(() => [...document.querySelectorAll('ul.gates, details.report')].filter(e => !e.closest('#piece-P1')).length);
  t('a verified piece draws no gates and no report', elsewhere === 0, String(elsewhere));
  t('no script error', errors.length === 0, errors.join('; '));
  await b.close();
  process.exit(fails ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
