// builds.cjs -- one card for a question and the piece building it, in a real
// browser: run by test/browser_run.rb as `node builds.cjs PAGE_URL BROWSER`
// against the ledger of test/support/builds_fixture.rb (O1, built by P2;
// P1 obsolete). Checks that Waiting on you holds the one card, the piece's
// part inside it and no card of its own; that Answer and start P2 posts the
// answer, waits for it to be accepted, then posts the start; and that an
// answer refused sends nothing more. Prints one ok/FAIL line per check;
// exit 1 on any FAIL.
const pw = require(process.env.PLAYWRIGHT_CORE);
const [url, which] = process.argv.slice(2);

(async () => {
  let fails = 0;
  const t = (n, ok, why) => { console.log((ok ? 'ok   ' : 'FAIL ') + which + ': ' + n + (ok || !why ? '' : ' -- ' + why)); if (!ok) fails++; };
  const b = which === 'chrome'
    ? await pw.chromium.launch({executablePath: process.env.CHROME})
    : await pw.firefox.launch({channel: 'moz-firefox', executablePath: process.env.FIREFOX});
  const errors = [];
  // a page whose posts to /say by the viewer's script are logged into SAID,
  // in the order they leave and come back: the page's own fetch is wrapped,
  // as Firefox's protocol gives no request body
  const open = async said => {
    const p = await b.newPage({viewport: {width: 1280, height: 900}});
    p.on('pageerror', e => errors.push(String(e)));
    await p.exposeFunction('saidHook', (k, body, status) => { said.push([k, new URLSearchParams(body), status]); });
    await p.addInitScript(() => {
      const real = window.fetch;
      window.fetch = async (u, init) => {
        const post = init && init.method === 'POST' && /\/say$/.test(new URL(u, location.href).pathname);
        if (post) await window.saidHook('sent', String(init.body), 0);
        const r = await real(u, init);
        if (post) await window.saidHook('back', String(init.body), r.status);
        return r;
      };
    });
    await p.goto(url);
    return p;
  };
  const until = async (fn, ms = 8000) => { const end = Date.now() + ms; while (Date.now() < end) { if (await fn()) return true; await new Promise(r => setTimeout(r, 100)); } return false; };

  // an answer refused: the start is never sent
  const refused = [];
  const r = await open(refused);
  await r.route('**/say', route => route.fulfill({status: 409, contentType: 'text/plain', body: 'refused'}));
  await r.locator('#q-O1 input[name="choice"]').first().check();
  await r.locator('#q-O1 button.a-answer-start').click();
  await until(async () => refused.filter(([k]) => k === 'back').length >= 1);
  await new Promise(res => setTimeout(res, 1500));
  t('an answer refused sends nothing more', refused.length > 0 && refused.every(([, body]) => body.get('ref') === 'O1' && !body.has('word')),
    JSON.stringify(refused.map(([k, body]) => [k, body.toString()])));
  await r.close();

  const said = [];
  const p = await open(said);
  const cards = await p.evaluate(() => [...document.querySelectorAll('section.waiting > ul.entries > li[id]')].map(li => li.id));
  t('Waiting on you holds the one card', JSON.stringify(cards) === '["q-O1"]', cards.join(' '));
  t('the piece has no card of its own', await p.locator('section.waiting #p-P2').count() === 0);
  const part = await p.evaluate(() => {
    const card = document.getElementById('q-O1'), piece = card?.querySelector('#builds-P2');
    const picker = card?.querySelector('input[name="choice"]'), button = card?.querySelector('button.a-answer-start');
    return piece && picker && button && {
      after: !!(picker.compareDocumentPosition(piece) & Node.DOCUMENT_POSITION_FOLLOWING),
      plan: piece.textContent.includes('the lexer the answer picks'), risk: piece.textContent.includes('4/10'),
      button: button.textContent.trim() };
  });
  t('the piece\'s plan and risk sit under the picker', part && part.after && part.plan && part.risk, JSON.stringify(part));
  t('one button says Answer and start P2', part && part.button === 'Answer and start P2', JSON.stringify(part));

  await p.locator('#q-O1 input[name="choice"]').first().check();
  await p.locator('#q-O1 button.a-answer-start').click();
  await until(async () => said.filter(([k]) => k === 'back').length >= 2);
  const steps = said.map(([k, body]) => k + ' ' + body.get('ref') + (body.get('word') ? ':' + body.get('word') : ''));
  t('the answer goes, is accepted, then the start goes',
    JSON.stringify(steps) === JSON.stringify(['sent O1', 'back O1', 'sent P2:start', 'back P2:start']), steps.join(', '));
  t('both are accepted', said.filter(([k]) => k === 'back').every(([, , status]) => status < 400),
    JSON.stringify(said.filter(([k]) => k === 'back').map(([, body, status]) => [body.get('ref'), status])));
  t('the answer carries its choice', said[0] && said[0][1].get('choice') === 'A = hand-written', said[0] && said[0][1].toString());
  t('the card says the answer is sent', await until(() => p.locator('#q-O1 .sent, #q-O1 .sent-line').count().then(n => n > 0)));
  t('no page error', errors.length === 0, errors.join(' | '));
  await b.close();
  process.exit(fails ? 1 : 0);
})().catch(e => { console.log('FAIL ' + which + ': ' + e.message); process.exit(1); });
