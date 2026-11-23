# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "ledger/journal"
require "ledger/waker_check"

# rake check:waker, the journal and process conditions: each is ok or warn
# over a sandbox journal and a stubbed process list.
class WakerCheckTest < Minitest::Test
    ROOT = "/srv/ledger"
    DIR = "/work/proj"
    RUNNING = "4242 /usr/local/bin/ruby -r bundler/setup -I #{ROOT}/lib " \
              "-r ledger/waker/main -e exit".freeze

    # A check whose file conditions are fixed answers.
    Fixed = Data.define(:lines)

    def setup
        @dir = Dir.mktmpdir("waker-check", SANDBOX)
        @journal = File.join(@dir, "journal.db")
        @db = Ledger::Journal.new(@journal)
        @ps = [RUNNING]
    end

    def teardown
        @db.close
        FileUtils.rm_rf(@dir)
    end

    def ledger(waker: true, closed: false)
        @db.db[:ledgers].insert(place: "#{DIR}/.claude", name: "", project: "p",
                                created_at: 1, waker:,
                                closed_at: closed ? 2 : nil)
    end

    def session(id, cwd: DIR)
        @db.db[:sessions].insert(session_id: id, cwd:, at: 1)
    end

    def stop(id, at: 5) = @db.db[:session_stops].insert(session_id: id, at:)

    def lines
        Ledger::WakerCheck.new(
            root: ROOT, journal: @journal, processes: -> { @ps },
            version: Fixed.new([[:ok, "claude", "v"]]),
            settings: Fixed.new([[:ok, "settings", "s"]])
        ).lines
    end

    def states(name) = lines.select { it[1] == name }.map(&:first)

    def test_no_ledger_on_is_one_line_and_skips_process_and_sessions
        ledger(waker: false)
        ledger(closed: true)
        @ps = []
        found = lines
        assert_includes found, [:ok, "waker", "no ledger has the waker on"]
        assert_empty(found.select { %w[process sessions].include?(it[1]) })
    end

    def test_process_running_is_ok_and_names_its_pid
        ledger
        session("a")
        process = lines.find { it[1] == "process" }
        assert_equal :ok, process[0]
        assert_includes process[2], "4242"
    end

    def test_process_of_another_checkout_warns
        ledger
        @ps = [RUNNING.sub(ROOT, "/other/ledger")]
        assert_equal [:warn], states("process")
    end

    def test_no_process_warns
        ledger
        @ps = []
        assert_equal [:warn], states("process")
    end

    def test_sessions_recorded_in_the_directory_is_ok
        ledger
        session("a")
        stop("a")
        assert_equal [:ok], states("sessions")
        assert_empty states("session")
    end

    def test_no_session_in_the_directory_warns
        ledger
        session("a", cwd: "/elsewhere")
        assert_equal [:warn], states("sessions")
    end

    def test_newest_stop_without_a_sessions_row_warns_naming_it
        ledger
        session("a")
        stop("a", at: 5)
        stop("cleared", at: 9)
        line = lines.find { it[1] == "session" }
        assert_equal :warn, line[0]
        assert_includes line[2], "cleared"
    end

    def test_a_missing_journal_warns_and_is_never_created
        File.delete(@journal)
        assert_equal [:warn], states("journal")
        refute_path_exists @journal
    end
end

# rake check:waker, the version and settings conditions, over a scratch
# record and settings file.
class WakerCheckFilesTest < Minitest::Test
    GOOD = {
        "crossSessionInbound" => "accept",
        "hooks" => Ledger::WakerInstall::HOOKS.to_h do |event, (word, _)|
            [event, [Ledger::WakerInstall.entry(word, "x")]]
        end
    }.freeze

    def setup
        @dir = Dir.mktmpdir("waker-check", SANDBOX)
        @settings = File.join(@dir, "settings.json")
        @record = File.join(@dir, "doorbell.json")
        File.write(@settings, JSON.generate(GOOD))
        File.write(@record, JSON.generate("claude_version" => "2.1.1"))
    end

    def teardown = FileUtils.rm_rf(@dir)

    def version(ask) = Ledger::WakerCheck::Version.new(record: @record, ask:)

    def settings = Ledger::WakerCheck::Settings.new(@settings).lines.first

    def test_version_equal_is_ok
        assert_equal :ok, version(-> { "2.1.1" }).lines.first[0]
    end

    def test_version_different_warns_naming_both
        line = version(-> { "2.1.9" }).lines.first
        assert_equal :warn, line[0]
        assert_includes line[2], "2.1.9"
        assert_includes line[2], "2.1.1"
    end

    def test_claude_not_on_path_warns
        missing = ->(*) { ["", false, "claude: not found"] }
        claude = Ledger::Waker::Claude.new(run: missing)
        line = version(-> { claude.version }).lines.first
        assert_equal :warn, line[0]
        assert_includes line[2], "not found"
    end

    def test_settings_complete_is_ok
        assert_equal :ok, settings[0]
    end

    def test_settings_missing_inbound_warns_naming_it
        File.write(@settings, JSON.generate(GOOD.except("crossSessionInbound")))
        assert_equal :warn, settings[0]
        assert_includes settings[2], "crossSessionInbound"
    end

    def test_settings_missing_hooks_warns_naming_them
        File.write(@settings, "{}")
        assert_includes settings[2], "Stop hook stamp"
        assert_includes settings[2], "SessionStart hook session-start"
    end

    def test_missing_settings_file_warns
        File.delete(@settings)
        assert_equal :warn, settings[0]
    end
end
