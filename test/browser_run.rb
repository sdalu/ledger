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
# firefox runs one; $LAN=1 runs without signing in, 127.0.0.1 being in the
# viewer's lan setting, where the default signs a user in. Run from the
# checkout:
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
require_relative "support/groups_fixture"
require_relative "support/long_fixture"

module BrowserRun
    ROOT = File.expand_path("..", __dir__)
    PASSWORD = "a long enough password"

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
        GROUPS = File.join(__dir__, "browser", "groups.cjs")
        LONG = File.join(__dir__, "browser", "long.cjs")

        def initialize(core, browsers)
            @core = core
            @browsers = browsers
        end

        def call(sandbox, cookie)
            shared = @browsers.map do |name, exe|
                check(sandbox, cookie, name, exe)
            end
            shared.all? & long_passes?(sandbox, cookie) &
                groups_pass?(sandbox, cookie)
        end

        private

        # The long page's check, once per browser, each on a ledger of its
        # own made after the shared checks, which read the index's first
        # queue entry and must not meet it.
        def long_passes?(sandbox, cookie)
            @browsers.map do |name, exe|
                next true unless File.executable?(exe)

                address = File.join(sandbox.dir, "long-#{name}", ".claude",
                                    "LEDGER.md")
                build_long(sandbox, address)
                lid = Digest::SHA1.hexdigest(address)[0, 10]
                system(env(sandbox, cookie), "node", LONG,
                       "#{sandbox.base}/l/#{lid}", name)
            end.all?
        end

        # The group buttons check, once per browser, on a ledger of its
        # own: two sets of three pieces awaiting the same words.
        def groups_pass?(sandbox, cookie)
            @browsers.map do |name, exe|
                next true unless File.executable?(exe)

                address = File.join(sandbox.dir, "groups-#{name}", ".claude",
                                    "LEDGER.md")
                build_groups(sandbox, address)
                lid = Digest::SHA1.hexdigest(address)[0, 10]
                system(env(sandbox, cookie), "node", GROUPS,
                       "#{sandbox.base}/l/#{lid}", name)
            end.all?
        end

        def build_groups(sandbox, address)
            journal = Ledger::Journal.open(sandbox.journal)
            GroupsFixture.build(journal, address)
        ensure
            journal&.close
        end

        def build_long(sandbox, address)
            journal = Ledger::Journal.open(sandbox.journal)
            LongFixture.build(journal, address)
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
            shared && pages
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
