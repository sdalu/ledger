# frozen_string_literal: true

# Sinatra as in a test, whatever the shell set (an empty RACK_ENV is
# :"", neither development nor production); neither mode.
ENV["RACK_ENV"] = "test"
%w[DEBUG PRODUCTION].each { ENV.delete(it) }

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "fileutils"
require "minitest/autorun"
require "rack/test"
require "tmpdir"

require "ledger_viewer"

# Nothing a test runs may reach a real ledger, the real store or the
# real local config: all of it is in this directory.
SANDBOX = Dir.mktmpdir("ledger-viewer-test")
Minitest.after_run { FileUtils.rm_rf(SANDBOX) }

# The machine's local file and certificate directory are under ~/.config,
# which the suite never reads or writes: the loader is pointed here.
ENV["LEDGER_VIEWER_LOCAL"] = File.join(SANDBOX, "app.local.rb")
File.write(ENV.fetch("LEDGER_VIEWER_LOCAL"),
           %({ tls_dir: #{File.join(SANDBOX, "tls").inspect} }\n))

# A viewer over a sandbox: one project with a ledger under `roots`, one
# ledger outside them, an empty store.
module Fixture
    SECRET = "x" * 40
    PASSWORD = "a long enough password"
    # Sesam's cookie is secure-only, so the browser talks https.
    HOST = { "HTTP_HOST" => "localhost", "REMOTE_ADDR" => "127.0.0.1",
             "HTTPS" => "on" }.freeze

    # One project with a ledger under the roots, one outside them.
    def self.projects(dir)
        %w[roots/alpha elsewhere/beta].each do |project|
            FileUtils.mkdir_p(File.join(dir, project, ".git"))
            File.write(File.join(dir, project, "LEDGER.md"), "# Ledger\n")
        end
    end

    def self.config(dir, **extra)
        projects(dir)
        LedgerViewer::Config.new(
            roots: [File.join(dir, "roots")], session_secret: SECRET,
            bind: "127.0.0.1:4599", store: File.join(dir, "data", "users.json"),
            ledger_py: File.expand_path("../../scripts/ledger.py", __dir__),
            python: "python3", dump_timeout: 20, session_days: 1,
            tls_dir: File.join(dir, "tls"), root: dir, **extra
        )
    end
end

class ViewerTest < Minitest::Test
    include Rack::Test::Methods

    def setup
        @dir = Dir.mktmpdir("viewer", SANDBOX)
        @config = Fixture.config(@dir)
        @db = LedgerViewer::Accounts.open(@config)
        @app = LedgerViewer::Web.configured(@config, db: @db).new
    end

    # Not the class: calling it memoises the middleware stack.
    attr_reader :app

    def request_headers = Fixture::HOST

    def https(path, verb = :get, body = nil, headers = {})
        header "Accept", "text/html" if headers.delete(:html)
        env = Fixture::HOST.merge(headers)
        send(verb, path, body, env)
    end

    def post_json(path, data)
        https(path, :post, JSON.generate(data),
              "CONTENT_TYPE" => "application/json")
    end

    # An invitation spent on a password, then signed in with it.
    def sign_in(name = "alice")
        token = LedgerViewer::Accounts.invite(@db, name)
        post_json("/session/invite", token:, password: Fixture::PASSWORD)
        post_json("/session/password", name:, password: Fixture::PASSWORD)
        token
    end
end
