#!/usr/bin/env ruby
# frozen_string_literal: true

# compare_inbox.rb -- the Ruby viewer's sends against the Python
# viewer's: the same forms posted to both, over two copies of the same
# ledgers, and what each answers and writes compared.
#
#     bundle exec ruby test/compare_inbox.rb
#
# Builds the fixture set of test/support/fixture_set.sh twice in a
# scratch directory (the ledgers of the Python viewer's own tests, among
# them one holding every kind of card), starts ledger-serve.py on a free
# port of 127.0.0.1 over one copy, and runs the Ruby app (rack-test,
# signed in) over the other. Posts to the rich ledger's /say and
# /say-all: an answer with a choice and comments, per-item picks, a word,
# a drop, a note, a piece comment, a proposed order, a word for several
# pieces, replaced answers and words, odd text (tab, CRLF, U+2028,
# emoji, bytes that are not UTF-8), and every refusal the rules have
# (400, 404, 409, 413, a wrong token). Nothing is written outside the
# scratch directory; the server is stopped at the end.
#
# Compared, case by case: the status, the Location (the ledger's name
# set aside) and, for an answer that is not a redirect, the page. Then
# the two PATH.inbox files, line by line, the `at` time set aside and
# nothing else.
#
# Not compared: a body with an invalid %-escape (`%zz`). The Python
# viewer keeps it as typed and files it; Rack refuses it before the
# route runs (400), and nothing is filed (test/inbox_test.rb).
#
# Exit 0 when everything is equal, 1 when it differs (each difference
# is printed), 2 when it cannot run.

require "fileutils"
require "json"
require "net/http"
require "open3"
require "socket"
require "tmpdir"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
ENV["RACK_ENV"] = "test"
require "ledger_viewer"
require "rack/test"

SCRIPTS = File.expand_path("../../scripts", __dir__)
FIXTURE = File.expand_path("support/fixture_set.sh", __dir__)
RICH = "rich/.claude/LEDGER.md"
SECRET = "x" * 40
PASSWORD = "a long enough password"
HOST = { "REMOTE_ADDR" => "127.0.0.1", "HTTPS" => "on" }.freeze

# One post: what is sent, and what is meant by it. A `raw` body is sent
# as it is; `token: false` sends a token that is not the session's;
# `lid` names another ledger.
Case = Struct.new(:name, :route, :pairs, :raw, :token, :lid) do
    def initialize(name, route, pairs = [], raw: nil, token: true, lid: nil)
        super(name, route, pairs, raw, token, lid)
    end
end

# The forms, in the order they are posted: refusals that depend on
# nothing sent yet first, then what is taken, then refusals that depend
# on it.
FIRST = [
    Case.new("unknown kind", "say", [%w[ref X9], %w[text x]]),
    Case.new("answer to an unasked ref", "say", [%w[ref O99], %w[text x]]),
    Case.new("choice not offered", "say", [%w[ref O1], %w[choice Z]]),
    Case.new("choice not offered, quote", "say",
             [%w[ref O1], ["choice", "it's"]]),
    Case.new("a choice where items are asked", "say",
             [%w[ref O2], ["choice", "A = keep"]]),
    Case.new("a pick not offered", "say", [%w[ref O2], %w[pick:S1 bogus]]),
    Case.new("answer to a question in preparation", "say",
             [%w[ref O7], ["choice", "A = a"]]),
    Case.new("replaces missing", "say", [%w[ref O6], %w[text again]]),
    Case.new("replaces incomplete", "say",
             [%w[ref O4], %w[replaces N1], ["choice", "A = one"]]),
    Case.new("nothing to send", "say", [%w[ref], ["text", "   "]])
].freeze

PIECES = [
    Case.new("a word not awaited", "say", [%w[ref P3], %w[word bogus]]),
    Case.new("a word on a piece awaiting none", "say",
             [%w[ref P4], %w[word commit]]),
    Case.new("drop of no piece", "say", [%w[ref P99], %w[word drop]]),
    Case.new("comment on a blocked piece", "say", [%w[ref P4], %w[text x]]),
    Case.new("comment on an unplanned piece", "say",
             [%w[ref P7], %w[text x]]),
    Case.new("order naming one piece", "say", [%w[ref order], %w[order P5]]),
    Case.new("order naming a piece twice", "say",
             [%w[ref order], ["order", "P5 P6 P6"]]),
    Case.new("give-all of one piece", "say-all",
             [%w[refs P2], %w[word commit]]),
    Case.new("give-all over a sent word", "say-all",
             [["refs", "P1 P2"], %w[word commit]]),
    Case.new("give-all over a piece that awaits other words", "say-all",
             [["refs", "P2 P4"], %w[word commit]]),
    Case.new("give-all of other", "say-all",
             [["refs", "P2 P3"], %w[word other]])
].freeze

SIZES = [
    Case.new("a box too long", "say", [%w[ref], ["text", "x" * 4001]]),
    Case.new("an empty body", "say", raw: ""),
    Case.new("a body too long", "say", raw: "x=#{"y" * 70_000}"),
    Case.new("a wrong token", "say",
             [%w[ref O1], ["choice", "A = the old one"], %w[text mine]],
             token: false),
    Case.new("an unknown ledger", "say", [%w[ref], %w[text x]],
             lid: "0123456789")
].freeze

ODD = "tab\there \u2028 line, é 😀 \u0001 \"q\" \\ / %41 & = + ;"

TAKEN = [
    Case.new("answer, choice and comments", "say",
             [%w[ref O1], ["choice", "A = the old one"],
              ["note:A = the old one", "why A"], ["text", "my reason"]]),
    Case.new("answer, picks", "say",
             [%w[ref O2], ["pick:S1", "A = keep"],
              ["pick:S2", "drop = remove"], %w[note:S2 gone]]),
    Case.new("answer, text only, CRLF", "say",
             [%w[ref O3], ["text", "free\r\ntext\r\n"]]),
    Case.new("answer, drop", "say", [%w[ref O8], %w[word drop]]),
    Case.new("word, replaced", "say",
             [%w[ref P1], %w[word commit], %w[replaces N5], %w[text go]]),
    Case.new("word, drop of a piece", "say",
             [%w[ref P6], %w[word drop], %w[text bye]]),
    Case.new("note", "say", [%w[ref], ["text", "a note"]]),
    Case.new("piece comment", "say", [%w[ref P5], %w[text comment]]),
    Case.new("order", "say", [%w[ref order], ["order", "P6, P5"]]),
    Case.new("give-all", "say-all", [["refs", "P2 P3"], %w[word commit]]),
    Case.new("answer, replaced", "say",
             [%w[ref O4], ["replaces", "N1 N2"],
              ["choice", "B = two (in your comment)"],
              ["note:B = two (in your comment)", "because"]]),
    Case.new("answer by items, replaced", "say",
             [%w[ref O5], %w[replaces N3], ["pick:X1", "A = one"]]),
    Case.new("odd text", "say", [%w[ref], ["text", ODD]]),
    Case.new("bytes that are not UTF-8", "say",
             raw: "token=TOKEN&ref=&text=a%FFb%ED%A0%80c%C3"),
    Case.new("a note after them", "say", [%w[ref], %w[text after]])
].freeze

LATER = [
    Case.new("answer replaced, replaces missing", "say",
             [%w[ref O4], ["choice", "A = one"]]),
    Case.new("give-all again", "say-all", [["refs", "P2 P3"], %w[word commit]])
].freeze

CASES = [*FIRST, *PIECES, *SIZES, *TAKEN, *LATER].freeze

# The urlencoded body of a case, as a browser writes one.
def body_of(pairs)
    pairs.map { |name, value| "#{escape(name)}=#{escape(value.to_s)}" }
         .join("&")
end

def escape(value)
    value.b.gsub(/[^A-Za-z0-9*._-]/n) do |byte|
        byte == " " ? "+" : format("%%%02X", byte.ord)
    end
end

# What the Python viewer answers, over HTTP.
class PythonSide
    def initialize(root)
        @root = root
        @port = free_port
    end

    def start
        reader, writer = IO.pipe
        script = File.join(SCRIPTS, "ledger-serve.py")
        @pid = Process.spawn("python3", script, "--port", @port.to_s, @root,
                             out: writer, err: writer)
        writer.close
        line = reader.gets.to_s
        raise "ledger-serve.py said #{line.inspect}" unless
            line.start_with?("http://")
    end

    def stop
        Process.kill("TERM", @pid)
        Process.wait(@pid)
    rescue SystemCallError
        nil
    end

    def lid = Digest::SHA1.hexdigest(File.join(@root, RICH))[0, 10]

    def token
        page = http(Net::HTTP::Get.new("/l/#{lid}"))
        page.body[/name="token" value="([^"]*)"/, 1]
    end

    # [status, Location, body] of a post of `body` to `path`.
    def post(path, body, token)
        request = Net::HTTP::Post.new(path)
        request["Origin"] = "http://127.0.0.1:#{@port}"
        request["Content-Type"] = "application/x-www-form-urlencoded"
        request.body = body.sub("TOKEN", token)
        answer = http(request)
        [answer.code.to_i, answer["Location"],
         answer.body.to_s.dup.force_encoding(Encoding::UTF_8)]
    end

    private

    def http(request)
        Net::HTTP.start("127.0.0.1", @port) { it.request(request) }
    end

    def free_port
        server = TCPServer.new("127.0.0.1", 0)
        server.addr[1].tap { server.close }
    end
end

# The Ruby app over the other copy, signed in, through rack-test.
class RubySide
    def initialize(root, dir)
        @root = root
        config = config(root, dir)
        db = LedgerViewer::Accounts.open(config)
        @session = Rack::Test::Session.new(
            LedgerViewer::Web.configured(config, db:).new
        )
        sign_in(db)
    end

    def lid = Digest::SHA1.hexdigest(File.join(@root, RICH))[0, 10]

    def token
        @session.get("/l/#{lid}", nil, HOST.merge("HTTP_HOST" => "localhost"))
        @session.last_response.body[/name="token" value="([^"]*)"/, 1]
    end

    def post(path, body, token)
        env = HOST.merge("HTTP_HOST" => "localhost",
                         "HTTP_ORIGIN" => "https://localhost",
                         "CONTENT_TYPE" => "application/x-www-form-urlencoded")
        @session.post(path, body.sub("TOKEN", token), env)
        answer = @session.last_response
        [answer.status, answer.headers["Location"], answer.body]
    end

    private

    def config(root, dir)
        LedgerViewer::Config.new(
            roots: [root], session_secret: SECRET, bind: "127.0.0.1:1",
            store: File.join(dir, "data", "users.json"),
            ledger_py: File.join(SCRIPTS, "ledger.py"), python: "python3",
            dump_timeout: 20, session_days: 1, tls_dir: File.join(dir, "tls"),
            root: dir
        )
    end

    def sign_in(db)
        invitation = LedgerViewer::Accounts.invite(db, "alice")
        [["/session/invite", { token: invitation, password: PASSWORD }],
         ["/session/password", { name: "alice", password: PASSWORD }]]
            .each do |path, data|
            @session.post(path, JSON.generate(data),
                          HOST.merge("HTTP_HOST" => "localhost",
                                     "CONTENT_TYPE" => "application/json"))
        end
    end
end

# One side of the comparison, with the token its forms carry.
Side = Struct.new(:server, :token) do
    def lid = server.lid

    # [status, Location, page] of a case, the ledger's name and the token
    # set aside, and the page too when the answer is a redirect.
    def answer(sent)
        body = sent.raw || body_of([%w[token TOKEN], *sent.pairs])
        path = "/l/#{sent.lid || lid}/#{sent.route}"
        status, location, page = server.post(path, body,
                                             sent.token ? token : "stale")
        [status, mask(location), status == 303 ? "" : mask(page)]
    end

    def mask(text) = text.to_s.gsub(lid, "LID").gsub(token, "TOKEN")
end

# Where two answers differ, or two inboxes.
module Differences
    def self.answers(left, right)
        return "  status #{left[0]} / #{right[0]}" if left[0] != right[0]
        return "  Location #{left[1].inspect} / #{right[1].inspect}" if
            left[1] != right[1]

        page(left[2], right[2])
    end

    def self.page(left, right)
        at = first(left, right)
        ["  page differs at #{at}:",
         "    python #{left[at - 20, 120].inspect}",
         "    ruby   #{right[at - 20, 120].inspect}"].join("\n")
    end

    def self.first(left, right)
        (0...left.length).find { left[it] != right[it] } || left.length
    end

    def self.inboxes(left, right)
        return [] if left == right

        at = first(left, right)
        ["PATH.inbox differs at line #{at + 1}:",
         "  python #{left[at].inspect}", "  ruby   #{right[at].inspect}"]
    end
end

# The two sides, the cases, and what differs.
class Comparison
    def initialize(dir)
        @dirs = %w[python ruby].map { File.join(dir, it) }
        @dirs.each { build(it) }
        @python = PythonSide.new(@dirs[0])
        @ruby = RubySide.new(@dirs[1], dir)
        @found = []
        @filed = 0
    end

    def run
        @python.start
        sides = [Side.new(@python, @python.token),
                 Side.new(@ruby, @ruby.token)]
        CASES.each { try(it, sides) }
        @found.concat(inbox_differences)
        report
    ensure
        @python.stop
    end

    private

    def report
        @found.each { puts it }
        puts "#{CASES.length} forms posted, #{@filed} taken, " \
             "#{@found.length} differences"
        @found.empty? ? 0 : 1
    end

    def build(dir)
        env = { "ledger" => File.join(SCRIPTS, "ledger.py") }
        out, status = Open3.capture2e(env, "sh", FIXTURE, dir)
        abort "fixture_set.sh failed:\n#{out}" unless status.success?
    end

    def try(sent, sides)
        left, right = sides.map { it.answer(sent) }
        @filed += 1 if left[0] == 303
        return if left == right

        @found << "#{sent.name}:\n#{Differences.answers(left, right)}"
    end

    def inbox_differences
        Differences.inboxes(*@dirs.map { lines(File.join(it, RICH)) })
    end

    # The inbox's lines, the time of each set aside.
    def lines(ledger)
        at = /\A(\{"id": "N\d+", )"at": "[^"]*"/
        File.read("#{ledger}.inbox", encoding: "UTF-8").scrub("?")
            .lines.map { |line| line.sub(at, '\\1"at": "AT"') }
    end
end

if $PROGRAM_NAME == __FILE__
    Dir.mktmpdir("compare-inbox") do |dir|
        exit Comparison.new(dir).run
    end
end
