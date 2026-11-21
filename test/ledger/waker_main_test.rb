# frozen_string_literal: true

require "stringio"

require_relative "helper"
require "ledger/waker/main"

# bin/ledger-waker's guards: a Claude Code other than the one the format
# was established on refuses the loop, naming both versions and
# --probe; a probe directory Claude Code does not trust refuses the
# probe, naming the one step, and nothing scratch is started.
class WakerMainTest < JournalTest
    # A `claude` that answers its version and nothing else.
    Versioned = Data.define(:version) do
        def agents = {}
    end

    def setup
        super
        @record = File.join(@dir, "doorbell.json")
        File.write(@record, JSON.generate(
                                "claude_version" => "2.1.329",
                                "line" => Ledger::Waker::Probe::FORMAT
                            ))
    end

    def main(version, *argv)
        out = StringIO.new
        err = StringIO.new
        code = Ledger::Waker::Main.new(out:, err:, record: @record,
                                       claude: Versioned.new(version:))
                                  .run(argv)
        [code, out.string, err.string]
    end

    def test_another_version_refuses_naming_both_and_the_probe
        code, _out, err = main("2.1.400", "--once")

        assert_equal 2, code
        assert_includes err, "Claude Code is 2.1.400"
        assert_includes err, "established on 2.1.329"
        assert_includes err, "bin/ledger-waker --probe"
    end

    def test_the_recorded_version_runs_a_pass
        assert_equal [0, "", ""], main("2.1.329", "--once")
    end

    def test_an_untrusted_probe_directory_is_refused_untouched
        dir = File.join(@dir, "probe")
        out = StringIO.new
        probe = Ledger::Waker::Probe.new(out:, record: @record, dir:,
                                         claude: Versioned.new(version: "x"),
                                         trust: ->(_) { :untrusted })

        assert_equal 2, probe.call
        assert_includes out.string, "does not trust #{dir}"
        assert_includes out.string, "cd #{dir} && claude"
        assert_includes out.string, "Yes, I trust this folder"
        assert_equal "2.1.329", Ledger::Waker.record(@record)["claude_version"]
    end

    def test_trust_is_read_from_the_directory_or_one_above
        config = File.join(@dir, "claude.json")
        accepted = { "hasTrustDialogAccepted" => true }
        projects = { "projects" => { "/home/u" => accepted } }
        File.write(config, JSON.generate(projects))
        trust = Ledger::Waker::Trust

        assert_equal :trusted, trust.of("/home/u/.cache/p", config:)
        assert_equal :untrusted, trust.of("/tmp/p", config:)
        assert_equal :unknown, trust.of("/tmp/p", config: "#{config}.none")
    end

    def test_the_record_in_the_repository_carries_a_version_and_the_line
        record = Ledger::Waker.record

        assert_match(/\A\d+\.\d+\.\d+\z/, record["claude_version"])
        assert_equal Ledger::Waker::Probe::FORMAT, record["line"]
    end
end
