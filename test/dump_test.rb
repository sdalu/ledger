# frozen_string_literal: true

require "test_helper"

class DumpTest < Minitest::Test
    LEDGER_PY = File.expand_path("../../scripts/ledger.py", __dir__)

    def dump(timeout: 20)
        LedgerViewer::Dump.new(python: "python3", script: LEDGER_PY, timeout:)
    end

    def test_a_ledger_that_is_not_there_reads_as_nil
        assert_nil dump.read(File.join(SANDBOX, "nowhere", "LEDGER.md"))
    end

    def test_a_file_that_is_no_ledger_reads_as_a_hash_of_nothing_much
        path = File.join(SANDBOX, "LEDGER.md")
        File.write(path, "# Ledger\n")
        data = dump.read(path)

        assert_instance_of Hash, data
        assert_empty data["questions"]
    end

    def test_an_engine_that_cannot_start_reads_as_nil
        broken = LedgerViewer::Dump.new(python: "/nonexistent/python",
                                        script: LEDGER_PY, timeout: 5)

        assert_nil broken.read(File.join(SANDBOX, "LEDGER.md"))
    end

    def test_a_slow_engine_reads_as_nil
        sleeper = LedgerViewer::Dump.new(python: "sleep", script: "5/x",
                                         timeout: 1)

        assert_nil sleeper.read("5")
    end
end
