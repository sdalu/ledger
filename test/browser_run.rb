# frozen_string_literal: true

# browser_run.rb -- the viewer's browser checks (test/browser/
# viewer.cjs, unchanged) against this viewer, in Chrome and Firefox: the
# ledger those checks expect made by bin/ledger's words in a sandbox
# journal (test/support/browser_fixture.rb), this app on a free port
# over it, a user made and signed in, and the browser handed that
# session cookie through test/browser_session.cjs, which stands in for
# playwright-core; test/browser_pages.cjs then opens the ledger's page
# and its pictures in each browser. The checks change the ledger by
# running bin/ledger against the journal in $LEDGER_JOURNAL.
# Needs node and playwright-core ($PLAYWRIGHT_CORE, default
# ~/node_modules/playwright-core) and the browsers ($CHROME, $FIREFOX);
# without them it says what it skips and exits 0. $ONLY=chrome or
# firefox runs one; $KEYS=1 runs only the key-renewal check, on a viewer
# whose mockup keys live KEYS_TTL seconds; $PANE=1 runs only the pane
# separator check, on the fixture's ledger; $CHECK=comment,groups runs
# only the named own-ledger checks (the tags of Checks::OWN); $LAN=1
# runs without signing in, 127.0.0.1 being in the viewer's lan setting,
# where the default signs a user in. Run from the checkout:
#   bundle exec ruby test/browser_run.rb

require "digest"
require "json"
require "net/http"
require "securerandom"
require "socket"
require "tmpdir"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "ledger_viewer"

require_relative "support/browser_fixture"
require_relative "support/builds_fixture"
require_relative "support/choices_fixture"
require_relative "support/groups_fixture"
require_relative "support/long_fixture"
require_relative "support/loop_fixture"
require_relative "support/risk_fixture"
require_relative "support/ties_fixture"

module BrowserRun
    ROOT = File.expand_path("..", __dir__)
    PASSWORD = "a long enough password"

    # The mockup keys' lifetime in seconds for the KEYS=1 run, whose one
    # check waits past it; every other check runs with the default.
    KEYS_TTL = "20"

    # The fixture's ledger, with its pictures and its inbox, in a journal
    # of the sandbox; this viewer's sandbox config over it.
    class Sandbox
        attr_reader :dir, :ledger, :port, :local, :journal

        def initialize(dir)
            @dir = dir
            @journal = File.join(dir, "journal.db")
            @ledger = fixture
            @port = free_port
            @local = config
        end

        def base = "http://127.0.0.1:#{port}"

        def lan? = ENV["LAN"] == "1"

        def log = File.join(dir, "server.log")

        private

        # The ledger at proj/.claude/LEDGER.md, as an address in the journal.
        def fixture
            path = File.join(dir, "proj", ".claude", "LEDGER.md")
            journal = Ledger::Journal.open(@journal)
            BrowserFixture.build(journal, path)
            path
        ensure
            journal&.close
        end

        def free_port
            server = TCPServer.new("127.0.0.1", 0)
            server.addr[1].tap { server.close }
        end

        # A secret of its own, the journal in the tmpdir: nothing under
        # ~/.config or ~/.local/state.
        def config
            file = File.join(dir, "app.local.rb")
            File.write(file, "#{settings.inspect}\n")
            file
        end

        def settings
            { bind: "127.0.0.1:#{port}",
              lan: lan? ? ["127.0.0.1"] : [],
              tls_dir: File.join(dir, "tls"),
              session_secret: SecureRandom.hex(32) }
        end
    end

    # The viewer in a child puma, and the session of a user signed in.
    class Server
        def initialize(sandbox)
            @sandbox = sandbox
            @env = { "LEDGER_VIEWER_LOCAL" => sandbox.local,
                     "LEDGER_JOURNAL" => sandbox.journal,
                     "RACK_ENV" => "test" }
            @env["LEDGER_MOCKUP_TTL"] = KEYS_TTL if ENV["KEYS"]
        end

        # Yields [cookie name, value] while the viewer runs, or nil when
        # the caller is on the lan and signs nothing.
        def run
            pid = start
            yield session
        ensure
            stop(pid)
        end

        private

        def stop(pid)
            return unless pid

            Process.kill("TERM", pid)
            Process.wait(pid)
        end

        def start
            log = @sandbox.log
            Process.spawn(@env, "bundle", "exec", "puma",
                          "-t", "0:#{LedgerViewer::THREADS}",
                          "-b", "tcp://127.0.0.1:#{@sandbox.port}",
                          # its own pidfile: config/puma.rb, which puma loads
                          # by default, names the viewer's
                          "--pidfile", File.join(@sandbox.dir, "puma.pid"),
                          "test/browser.ru", chdir: ROOT, out: log, err: log)
        end

        # Signed in, once the viewer answers.
        def session
            wait
            sign_in unless @sandbox.lan?
        end

        def wait
            100.times do
                Net::HTTP.get_response(URI("#{@sandbox.base}/health"))
                return
            rescue SystemCallError
                sleep 0.1
            end
            abort "the viewer did not start: #{File.read(@sandbox.log)}"
        end

        # A user invited from the store the server reads, then signed in
        # as a browser does: JSON POSTs from the app's own origin.
        def sign_in
            journal = Ledger::Journal.open(@sandbox.journal)
            store = LedgerViewer::Accounts.open(journal)
            token = LedgerViewer::Accounts.invite(store, "alice")
            post("/session/invite", token:, password: PASSWORD)
            reply = post("/session/password", name: "alice",
                                              password: PASSWORD)
            pair = reply.get_fields("set-cookie").to_a.first.to_s
                        .match(/\A([^=]+)=([^;]*)/)
            abort "no session cookie: #{reply.code}" unless pair
            pair.captures
        end

        def post(path, data)
            uri = URI("#{@sandbox.base}#{path}")
            request = Net::HTTP::Post.new(
                uri, "Content-Type" => "application/json",
                     "Origin" => @sandbox.base,
                     "Sec-Fetch-Site" => "same-origin"
            )
            request.body = JSON.generate(data)
            Net::HTTP.start(uri.host, uri.port) { |http| http.request(request) }
        end
    end

    # The shared browser test, once per browser, then every page.
    class Checks
        SHIM = File.join(__dir__, "browser_session.cjs")
        VIEWER = File.join(__dir__, "browser", "viewer.cjs")
        PAGES = File.join(__dir__, "browser_pages.cjs")
        SIGN_IN = File.join(__dir__, "browser", "sign_in.cjs")
        GROUPS = File.join(__dir__, "browser", "groups.cjs")
        LONG = File.join(__dir__, "browser", "long.cjs")
        CHOICES = File.join(__dir__, "browser", "choices.cjs")
        RISK = File.join(__dir__, "browser", "risk.cjs")
        LOOP = File.join(__dir__, "browser", "loop.cjs")
        KEYS = File.join(__dir__, "browser", "keys.cjs")
        PANE = File.join(__dir__, "browser", "pane.cjs")
        BUILDS = File.join(__dir__, "browser", "builds.cjs")
        COMMENT = File.join(__dir__, "browser", "comment_only.cjs")
        SHOWN = File.join(__dir__, "browser", "groups_shown.cjs")
        TIES = File.join(__dir__, "browser", "ties.cjs")
        # [tag, fixture, script] of the checks that each run on a ledger
        # of their own, once per browser, after the shared checks, which
        # read the index's first queue entry and must not meet them; the
        # risk and builds checks send words, which the next must not meet,
        # so they are last, builds reading only its own ledger.
        OWN = [["long", LongFixture, LONG], ["groups", GroupsFixture, GROUPS],
               ["choices", ChoicesFixture, CHOICES],
               ["loop", LoopFixture, LOOP],
               ["comment", ChoicesFixture, COMMENT],
               ["shown", GroupsFixture, SHOWN],
               ["ties", TiesFixture, TIES],
               ["risk", RiskFixture, RISK],
               ["builds", BuildsFixture, BUILDS]].freeze

        def initialize(core, browsers)
            @core = core
            @browsers = browsers
        end

        def call(sandbox, cookie)
            return keys_pass?(sandbox, cookie) if ENV["KEYS"]
            return pane_pass?(sandbox, cookie) if ENV["PANE"]
            return chosen_pass?(sandbox, cookie) if ENV["CHECK"]

            shared = @browsers.map do |name, exe|
                check(sandbox, cookie, name, exe)
            end
            own = OWN.map { own_passes?(sandbox, cookie, *it) }
            shared.all? & own.all?
        end

        private

        # The key-renewal check alone, in each browser, against a viewer
        # booted with the short key lifetime (KEYS=1 starts it so).
        def keys_pass?(sandbox, cookie)
            @browsers.map do |name, exe|
                next true unless File.executable?(exe)

                system(env(sandbox, cookie).merge(
                           "LEDGER_MOCKUP_TTL" => KEYS_TTL
                       ), "node", KEYS, sandbox.base, name)
            end.all?
        end

        # The pane separator's check alone, in each browser, on the
        # fixture's ledger (PANE=1 starts it so).
        def pane_pass?(sandbox, cookie)
            @browsers.map do |name, exe|
                next true unless File.executable?(exe)

                system(env(sandbox, cookie), "node", PANE, sandbox.base,
                       sandbox.ledger, name)
            end.all?
        end

        # The own-ledger checks named by CHECK (tags, comma-separated)
        # alone; a tag that names none is an error, not a silent pass.
        def chosen_pass?(sandbox, cookie)
            tags = ENV.fetch("CHECK").split(",")
            unknown = tags - OWN.map(&:first)
            abort "CHECK names no check: #{unknown.join(", ")}" unless
                unknown.empty?

            OWN.select { tags.include?(it.first) }
               .map { own_passes?(sandbox, cookie, *it) }.all?
        end

        # One script's check, once per browser, on a ledger of its own
        # made by FIXTURE: TAG names its directory.
        def own_passes?(sandbox, cookie, tag, fixture, script)
            @browsers.map do |name, exe|
                next true unless File.executable?(exe)

                address = File.join(sandbox.dir, "#{tag}-#{name}", ".claude",
                                    "LEDGER.md")
                build(sandbox, fixture, address)
                lid = Digest::SHA1.hexdigest(address)[0, 10]
                system(env(sandbox, cookie), "node", script,
                       "#{sandbox.base}/l/#{lid}", name)
            end.all?
        end

        def build(sandbox, fixture, address)
            journal = Ledger::Journal.open(sandbox.journal)
            fixture.build(journal, address)
        ensure
            journal&.close
        end

        def check(sandbox, cookie, name, exe)
            unless File.executable?(exe)
                puts "skip #{name}: #{exe} not found"
                return true
            end
            env = env(sandbox, cookie)
            shared = system(env, "node", VIEWER, sandbox.base, sandbox.ledger,
                            name)
            pages = system(env, "node", PAGES, sandbox.base, name)
            sign_in = system(env, "node", SIGN_IN, sandbox.base, name)
            shared && pages && sign_in
        end

        def env(sandbox, cookie)
            { "LEDGER_JOURNAL" => sandbox.journal,
              "PLAYWRIGHT_CORE" => SHIM, "PLAYWRIGHT_REAL" => @core,
              "CHROME" => @browsers["chrome"],
              "FIREFOX" => @browsers["firefox"],
              "PLAYWRIGHT_BROWSERS_PATH" =>
                  ENV.fetch("PLAYWRIGHT_BROWSERS_PATH", "0"),
              "SESSION_COOKIE" => JSON.generate(cookie),
              "SESSION_URL" => sandbox.base }
        end
    end

    def self.main
        core = ENV.fetch("PLAYWRIGHT_CORE",
                         File.expand_path("~/node_modules/playwright-core"))
        return skip(core) unless node? && File.directory?(core)

        checks = Checks.new(core, browsers)
        passed = Dir.mktmpdir("viewer-browser") { run(it, checks) }
        passed ? 0 : 1
    end

    def self.run(dir, checks)
        sandbox = Sandbox.new(dir)
        Server.new(sandbox).run { |cookie| checks.call(sandbox, cookie) }
    end

    def self.browsers
        found = { "chrome" => ENV.fetch("CHROME", "/usr/local/bin/chrome"),
                  "firefox" => ENV.fetch("FIREFOX",
                                         "/usr/local/bin/firefox") }
        only = ENV.fetch("ONLY", nil)
        only ? found.slice(only) : found
    end

    def self.node?
        ENV.fetch("PATH", "").split(":").any? do |dir|
            File.executable?(File.join(dir, "node"))
        end
    end

    def self.skip(core)
        puts "skip browser checks: node or playwright-core (#{core}) " \
             "not found"
        0
    end
end

exit BrowserRun.main
