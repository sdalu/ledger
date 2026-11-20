# frozen_string_literal: true

# browser_run.rb -- the Python viewer's browser checks (tests/browser/
# viewer.cjs, unchanged) against this viewer, in Chrome and Firefox: the
# same fixture, this app on a free port over a sandbox config and store,
# a user made and signed in, and the browser handed that session cookie
# through test/browser_session.cjs, which stands in for playwright-core.
# Needs node and playwright-core ($PLAYWRIGHT_CORE, default
# ~/node_modules/playwright-core) and the browsers ($CHROME, $FIREFOX);
# without them it says what it skips and exits 0. $ONLY=chrome or
# firefox runs one; $LAN=1 runs without signing in, 127.0.0.1 being in the
# viewer's lan setting, where the default signs a user in. Run from the
# checkout:
#   bundle exec ruby test/browser_run.rb

require "fileutils"
require "json"
require "net/http"
require "open3"
require "securerandom"
require "socket"
require "tmpdir"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "ledger_viewer"

module BrowserRun
    ROOT = File.expand_path("..", __dir__)
    SKILL = File.expand_path("..", ROOT)
    PASSWORD = "a long enough password"

    # The fixture of the Python run (the same shell function, the engine
    # in scripts/ledger.py) and this viewer's sandbox config over it.
    class Sandbox
        attr_reader :dir, :ledger, :port, :local

        def initialize(dir)
            @dir = dir
            @ledger = fixture
            @port = free_port
            @local = config
        end

        def base = "http://127.0.0.1:#{port}"

        def lan? = ENV["LAN"] == "1"

        def log = File.join(dir, "server.log")

        private

        def fixture
            script = ". #{SKILL}/tests/viewer-fixture.sh; " \
                     "ledger=#{SKILL}/scripts/ledger.py; " \
                     "make_fixture #{dir}"
            out, status = Open3.capture2("sh", "-c", script)
            abort "fixture failed" unless status.success?
            out.strip
        end

        def free_port
            server = TCPServer.new("127.0.0.1", 0)
            server.addr[1].tap { server.close }
        end

        # Roots the fixture, store in the tmpdir, a secret of its own:
        # nothing under ~/.config.
        def config
            file = File.join(dir, "app.local.rb")
            File.write(file, "#{settings.inspect}\n")
            file
        end

        def settings
            { bind: "127.0.0.1:#{port}", roots: [File.join(dir, "proj")],
              lan: lan? ? ["127.0.0.1"] : [],
              store: File.join(dir, "data", "users.json"),
              tls_dir: File.join(dir, "tls"),
              session_secret: SecureRandom.hex(32) }
        end
    end

    # The viewer in a child puma, and the session of a user signed in.
    class Server
        def initialize(sandbox)
            @sandbox = sandbox
            @env = { "LEDGER_VIEWER_LOCAL" => sandbox.local,
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
                          "config.ru", chdir: ROOT, out: log, err: log)
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
            config = LedgerViewer::Config.load(local: @sandbox.local)
            store = LedgerViewer::Accounts.open(config)
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

    # The shared browser test, once per browser.
    class Checks
        SHIM = File.join(__dir__, "browser_session.cjs")
        VIEWER = File.join(SKILL, "tests", "browser", "viewer.cjs")

        def initialize(core, browsers)
            @core = core
            @browsers = browsers
        end

        def call(sandbox, cookie)
            @browsers.map { |name, exe| check(sandbox, cookie, name, exe) }
                     .all?
        end

        private

        def check(sandbox, cookie, name, exe)
            unless File.executable?(exe)
                puts "skip #{name}: #{exe} not found"
                return true
            end
            system(env(sandbox, cookie), "node", VIEWER, sandbox.base,
                   sandbox.ledger, name)
        end

        def env(sandbox, cookie)
            { "PLAYWRIGHT_CORE" => SHIM, "PLAYWRIGHT_REAL" => @core,
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
        passed = Dir.mktmpdir("viewer-browser") do |dir|
            sandbox = Sandbox.new(dir)
            Server.new(sandbox).run { |cookie| checks.call(sandbox, cookie) }
        end
        passed ? 0 : 1
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
