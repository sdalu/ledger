// pane.cjs -- the separator on the picture pane's left edge: run by
// test/browser_run.rb with PANE=1 as `node pane.cjs BASE LEDGER BROWSER`.
// A picture opens in the pane; dragging the separator 200 px left widens
// the pane and the page's padding follows; ArrowRight narrows it by 2 %; a
// reload keeps the width; Home resets it to 50 %; no horizontal scroll at
// 1280 px. $PANE_SHOT names a PNG to save of the pane as first opened.
// Prints one ok/FAIL line per check; exit 1 on any FAIL.
const pw = require(process.env.PLAYWRIGHT_CORE);
const crypto = require('crypto');
const [base, ledger, which] = process.argv.slice(2);
const page = '/l/' + crypto.createHash('sha1').update(ledger).digest('hex').slice(0, 10);

(async () => {
  let fails = 0;
  const t = (n, ok, why) => {
    console.log((ok ? 'ok   ' : 'FAIL ') + which + ': ' + n + (ok || !why ? '' : ' -- ' + why));
    if (!ok) fails++;
  };
  const b = which === 'chrome'
    ? await pw.chromium.launch({executablePath: process.env.CHROME})
    : await pw.firefox.launch({channel: 'moz-firefox', executablePath: process.env.FIREFOX});
  const p = await b.newPage({viewport: {width: 1280, height: 900}});
  const errors = [];
  p.on('pageerror', e => errors.push(String(e)));
  const open = async () => {
    await p.goto(base + page);
    await p.locator('#q-O1 button.a-expand[data-kind="page"]').click();
    await p.locator('aside.mock-pane').waitFor();
  };
  // the pane's width as a share of the window, the page's padding beside it
  const state = () => p.evaluate(() => {
    const pane = document.querySelector('aside.mock-pane');
    const pad = parseFloat(getComputedStyle(document.body).paddingInlineEnd);
    const rem = parseFloat(getComputedStyle(document.documentElement).fontSize);
    const w = pane.getBoundingClientRect().width;
    return {pct: 100 * w / innerWidth, gap: pad - w - rem,
            now: pane.querySelector('[role="separator"]')?.getAttribute('aria-valuenow'),
            scroll: document.documentElement.scrollWidth - document.documentElement.clientWidth};
  });
  await p.goto(base + page);
  await p.evaluate(() => { try { localStorage.clear(); } catch (e) {} });
  await open();
  if (process.env.PANE_SHOT) await p.screenshot({path: process.env.PANE_SHOT});
  const sep = p.locator('aside.mock-pane [role="separator"]');
  t('a separator sits on the pane, vertical, focusable, with its bounds',
    await sep.count() === 1 && await sep.evaluate(e => e.getAttribute('aria-orientation') === 'vertical'
      && e.tabIndex === 0 && e.getAttribute('aria-valuemin') === '33' && e.getAttribute('aria-valuemax') === '80'));
  let s = await state();
  t('it starts at 50 %', Math.abs(s.pct - 50) < 0.5 && s.now === '50', JSON.stringify(s));
  const box = await sep.boundingBox();
  t('its hit area is 24 px wide', !!box && Math.round(box.width) === 24, JSON.stringify(box));
  if (box) {
    const x = box.x + box.width / 2, y = box.y + box.height / 2;
    await p.mouse.move(x, y);
    await p.mouse.down();
    await p.mouse.move(x - 100, y, {steps: 5});
    await p.mouse.move(x - 200, y, {steps: 5});
    await p.mouse.up();
  }
  s = await state();
  t('dragging 200 px left widens the pane by 200 px and the page padding follows',
    Math.abs(s.pct - (50 + 100 * 200 / 1280)) < 0.6 && Math.abs(s.gap) < 1, JSON.stringify(s));
  const wide = s.pct;
  await sep.focus();
  await p.keyboard.press('ArrowRight');
  s = await state();
  t('ArrowRight narrows it by 2 %', Math.abs(s.pct - (wide - 2)) < 0.6 && Math.abs(s.gap) < 1, JSON.stringify(s));
  const kept = s.pct;
  await open();
  s = await state();
  t('a reload keeps the width', Math.abs(s.pct - kept) < 0.6 && Math.abs(s.gap) < 1, JSON.stringify(s));
  await p.locator('aside.mock-pane [role="separator"]').focus();
  await p.keyboard.press('Home');
  s = await state();
  t('Home resets it to 50 %', Math.abs(s.pct - 50) < 0.5 && s.now === '50', JSON.stringify(s));
  await p.keyboard.press('ArrowLeft');
  await p.locator('aside.mock-pane [role="separator"]').dblclick();
  s = await state();
  t('a double-click resets it to 50 %', Math.abs(s.pct - 50) < 0.5, JSON.stringify(s));
  t('no horizontal scroll at 1280 px', s.scroll <= 0, JSON.stringify(s));
  await p.click('aside.mock-pane button.a-full');
  t('the separator is hidden in the full window', !(await p.locator('aside.mock-pane [role="separator"]').isVisible()));
  t('no script error', errors.length === 0, errors.join('; '));
  await b.close();
  process.exit(fails ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
