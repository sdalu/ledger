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

# Nothing a test runs may reach the real journal or the real local
# config: all of it is in this directory.
SANDBOX = Dir.mktmpdir("ledger-viewer-test")
Minitest.after_run { FileUtils.rm_rf(SANDBOX) }
ENV["LEDGER_JOURNAL"] = File.join(SANDBOX, "journal.db")

# The machine's local file and certificate directory are under ~/.config,
# which the suite never reads or writes: the loader is pointed here.
ENV["LEDGER_VIEWER_LOCAL"] = File.join(SANDBOX, "app.local.rb")
File.write(ENV.fetch("LEDGER_VIEWER_LOCAL"),
           %({ tls_dir: #{File.join(SANDBOX, "tls").inspect} }\n))

# A viewer over a sandbox: a journal of its own holding one live
# ledger, alpha, and no user.
module Fixture
    SECRET = "x" * 40
    PASSWORD = "a long enough password"
    # Sesam's cookie is secure-only, so the browser talks https.
    HOST = { "HTTP_HOST" => "localhost", "REMOTE_ADDR" => "127.0.0.1",
             "HTTPS" => "on" }.freeze

    def self.config(dir, **extra)
        LedgerViewer::Config.new(
            session_secret: SECRET, bind: "127.0.0.1:4599", session_days: 1,
            tls_dir: File.join(dir, "tls"), root: dir, **extra
        )
    end

    # The journal of `dir`, opened as the viewer opens one.
    def self.journal(dir)
        Ledger::Journal.open(File.join(dir, "state", "journal.db"),
                             busy_ms: LedgerViewer::Accounts::BUSY_MS)
    end

    # A live ledger at ADDRESS in JOURNAL with its first event, as `new`
    # makes one: every ledger of the journal has an event.
    def self.ledger(journal, address, project:)
        journal.transaction do
            journal.create_ledger(address, project:)
            Ledger::Write.run(journal, address, "new", []) { nil }
        end
    end

    # The live ledger alpha, its address under `dir`.
    def self.alpha(dir) = File.join(dir, "alpha", "LEDGER.md")
end

class ViewerTest < Minitest::Test
    include Rack::Test::Methods

    def setup
        @dir = Dir.mktmpdir("viewer", SANDBOX)
        @config = Fixture.config(@dir)
        @journal = Fixture.journal(@dir)
        Fixture.ledger(@journal, Fixture.alpha(@dir), project: "alpha")
        @db = LedgerViewer::Accounts.open(@journal)
        @app = LedgerViewer::Web.configured(@config, journal: @journal).new
    end

    def teardown = @journal.close

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
