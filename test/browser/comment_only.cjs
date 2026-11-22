// comment_only.cjs -- Send comment only on a question, in a real browser:
// run by test/browser_run.rb as `node comment_only.cjs PAGE_URL BROWSER`
// against the ledger of test/support/choices_fixture.rb (O1 with options
// A, B, C). The button sits beside Send answer, appears once the overall
// comment holds text, files the comment as a comment on the question
// (the card keeps its picker, shows the asked line, stays open) and
// empties the box; with script off it never shows. Prints one ok/FAIL
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
  const only = p.locator('#q-O1 button.a-comment-only');
  const box = p.locator('#q-O1 details.overall textarea');
  t('one Send comment only button, hidden while the comment is empty',
    await only.count() === 1 && await only.isHidden());
  await p.locator('#q-O1 details.overall summary').click();
  await box.fill('is B cheaper than C?');
  t('the button shows once the comment holds text', await only.isVisible());
  const place = await p.evaluate(() => {
    const row = document.querySelector('#q-O1 details.overall').closest('form').querySelector(':scope > .actions');
    return [...row.querySelectorAll('button')].filter(x => x.offsetParent).map(x => x.textContent.trim());
  });
  t('it sits beside Send answer', place.length === 2 && /^Send answer/.test(place[0]) && place[1] === 'Send comment only', JSON.stringify(place));
  await box.fill('   ');
  t('a blank comment hides it again', await only.isHidden());
  await box.fill('is B cheaper than C?');
  await p.locator('#q-O1 input[type="radio"]').nth(1).check();
  await only.click();
  await p.waitForSelector('#q-O1 .asked-line');
  const after = await p.evaluate(() => {
    const c = document.querySelector('#q-O1');
    return {
      asked: [...c.querySelectorAll('.asked-line')].map(x => x.textContent),
      sent: c.querySelectorAll('.sent, .sent-line').length,
      collapsed: c.classList.contains('is-collapsed'),
      radios: c.querySelectorAll('form.say input[type="radio"]').length,
      picked: c.querySelector('form.say input[type="radio"]:checked')?.value ?? null,
      text: c.querySelector('details.overall textarea').value,
      button: c.querySelector('button.a-comment-only').hidden };
  });
  t('the comment is filed as a question asked, not an answer',
    after.asked.length === 1 && after.sent === 0, JSON.stringify(after));
  t('the card stays open with its picker and the pick kept', !after.collapsed && after.radios === 3 && /^B/.test(after.picked || ''), JSON.stringify(after));
  t('the comment box is empty and the button hidden again', after.text === '' && after.button, JSON.stringify(after));
  await p.reload();
  t('after a reload the question is still open and asked once',
    await p.locator('#q-O1 form.say input[type="radio"]').count() === 3
    && await p.locator('#q-O1 .asked-line').count() === 1);
  const off = await b.newContext({javaScriptEnabled: false, viewport: {width: 1280, height: 900}});
  const q = await off.newPage();
  await q.goto(url);
  t('with script off the question shows and the button does not', await q.locator('#q-O1').count() === 1 && await q.locator('#q-O1 button.a-comment-only').isHidden());
  await b.close();
  process.exit(fails ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
