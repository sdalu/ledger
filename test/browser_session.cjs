// browser_session.cjs -- stands in for playwright-core under viewer.cjs
// (PLAYWRIGHT_CORE points here): the real library, but every page a
// browser opens carries the signed-in session cookie, which the shared
// test has no way to carry. Set by test/browser_run.rb:
// PLAYWRIGHT_REAL the real library, SESSION_COOKIE a JSON [name, value] or null,
// SESSION_URL the viewer's base URL.
const real = require(process.env.PLAYWRIGHT_REAL);
// null: a lan caller, which carries none.
const cookie = JSON.parse(process.env.SESSION_COOKIE);

// A context of its own holding the cookie, as the shared test's
// newContext(options) and newPage(options) ask: a context opened for a
// script-off visit signs in as well.
const signedIn = (browser) => {
  const open = browser.newContext.bind(browser);
  browser.newContext = async (options) => {
    const context = await open(options);
    if (cookie) {
      await context.addCookies([{ name: cookie[0], value: cookie[1], url: process.env.SESSION_URL,
                                  httpOnly: true, secure: true, sameSite: 'Lax' }]);
    }
    return context;
  };
  browser.newPage = async (options) => (await browser.newContext(options)).newPage();
  return browser;
};

const launcher = (type) => ({
  launch: async (options) => signedIn(await type.launch(options)),
});

module.exports = { chromium: launcher(real.chromium), firefox: launcher(real.firefox) };
