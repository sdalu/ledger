// sign_in.cjs -- the sign-in and invitation pages opened with a malformed
// fragment ("#%", a cut invitation link), in a real browser: run by
// test/browser_run.rb as `node sign_in.cjs BASE BROWSER`. The decode of the
// fragment must not stop the page's script: no page error, the submit
// listener answers, and a submit, with script on or off, never navigates
// to a URL that carries the password. Prints one ok/FAIL line per check;
// exit 1 on any FAIL.
const pw = require(process.env.PLAYWRIGHT_CORE);
const [base, which] = process.argv.slice(2);
const SECRET = 'wrong-password-marker';

(async () => {
  let fails = 0;
  const t = (n, ok, why) => { console.log((ok ? 'ok   ' : 'FAIL ') + which + ': ' + n + (ok || !why ? '' : ' -- ' + why)); if (!ok) fails++; };
  const b = which === 'chrome'
    ? await pw.chromium.launch({executablePath: process.env.CHROME})
    : await pw.firefox.launch({channel: 'moz-firefox', executablePath: process.env.FIREFOX});
  const clean = (url) => !url.includes(SECRET) && !url.includes('?');

  // script on: the listener is attached, the refusal is shown in place
  const p = await b.newPage();
  const errors = [];
  p.on('pageerror', e => errors.push(String(e)));
  await p.goto(base + '/sign-in#%');
  await p.fill('input[name=name]', 'nobody');
  await p.fill('input[name=password]', SECRET);
  await p.click('form button');
  await p.waitForSelector('.problem:not([hidden])', {timeout: 10000}).catch(() => null);
  t('sign-in#%: no page error', errors.length === 0, errors.join('; '));
  t('sign-in#%: the submit listener shows the refusal', await p.locator('.problem:not([hidden])').count() === 1);
  t('sign-in#%: the URL carries no password', clean(p.url()), p.url());

  errors.length = 0;
  await p.goto(base + '/invite#%');
  await p.waitForSelector('.problem:not([hidden])', {timeout: 10000}).catch(() => null);
  t('invite#%: no page error', errors.length === 0, errors.join('; '));
  t('invite#%: the empty token is refused in place', await p.locator('.problem:not([hidden])').count() === 1);
  t('invite#%: the form posts', await p.getAttribute('form', 'method') === 'post');
  await p.close();

  // script off: the form still never goes by GET
  const ctx = await b.newContext({javaScriptEnabled: false});
  const q = await ctx.newPage();
  await q.goto(base + '/sign-in#%');
  t('sign-in without script: method is post', await q.getAttribute('form', 'method') === 'post');
  await q.fill('input[name=name]', 'nobody');
  await q.fill('input[name=password]', SECRET);
  await q.click('form button');
  await q.waitForLoadState('load').catch(() => null);
  t('sign-in without script: the URL carries no password', clean(q.url()), q.url());
  await ctx.close();
  await b.close();
  process.exit(fails ? 1 : 0);
})().catch(e => { console.log('FAIL ' + which + ': ' + e.message); process.exit(1); });
