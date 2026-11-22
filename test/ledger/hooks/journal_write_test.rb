# frozen_string_literal: true

require_relative "helper"
require "ledger/hooks/journal_name"

# journal-write: a command writing the journal by hand is denied, naming
# the bin/ledger commands; reading it, and bin/ledger itself, pass. %J
# stands for the journal's path, %D for its directory.
class JournalWriteTest < HookTest
    WRITES = ["sqlite3 %J 'delete from pieces'",
              "sqlite3 $LEDGER_JOURNAL < fix.sql",
              "echo x > %J-wal",
              "cd %D && sqlite3 journal.db .dump",
              "cp /tmp/backup.db %J",
              "mv %J /tmp/old.db",
              "rm -f %J-shm",
              "printf x | tee -a %J",
              "sed -i.bak s/a/b/ %J",
              "sh -c 'sqlite3 %J vacuum'",
              "eval sqlite3 %J vacuum",
              "ruby -e 'Sequel.sqlite(\"%J\")[:pieces].delete'",
              "python3 -c 'import sqlite3; sqlite3.connect(\"%J\")'",
              "python3 - <<EOF\nopen(\"%J\", \"w\")\nEOF",
              "nice -n 19 sqlite3 %J vacuum",
              "nice -10 rm %J",
              "/opt/bin/low-priority sqlite3 %J vacuum",
              "timeout 60 sqlite3 %J vacuum",
              "timeout -s KILL 60 rm %J",
              "nohup rm %J",
              "time sqlite3 %J vacuum",
              "echo $(rm %J)",
              "echo `rm %J`",
              "echo \"$(echo $(rm %J))\"",
              "echo $(echo $(echo $(echo $(rm %J))))",
              "bin/ledger show X > %J",
              "env -i sqlite3 %J vacuum",
              "env -u HOME A=b rm %J",
              "sudo -u root rm %J",
              "sudo -E nice -n 5 rm %J",
              "if true; then rm %J; fi",
              "if false; then :; else rm %J; fi",
              "while rm %J; do :; done",
              "until true; do rm %J; done",
              "for x in a; do rm %J; done",
              "env -S 'x y' %J",
              "sudo -s %J"].freeze

    PASSES = ["sqlite3 -readonly %J 'select * from pieces'",
              "cp %J /tmp/backup.db",
              "ls -l %J\necho done",
              "bin/ledger piece /work/alpha/LEDGER.md P1 --status out",
              "sh bin/ledger check /work/alpha/LEDGER.md > /tmp/out",
              "ruby -e 'p File.size(\"%J\")'",
              "sqlite3 /tmp/other/journal.db 'delete from x'",
              "echo journal.db is where it lives",
              "nice -n 19 sqlite3 -readonly %J .dump",
              "ls %J",
              "timeout 5 ls %J",
              "echo $(ls %J)",
              "bin/ledger show X > /tmp/out",
              "nice -n 5 bin/ledger piece /work/alpha/LEDGER.md P1",
              "if true; then ls %J; fi"].freeze

    def journal = ENV.fetch("LEDGER_JOURNAL")

    def decision(command)
        command = command.gsub("%J", journal)
                         .gsub("%D", File.dirname(journal))
        answer = hook("journal-write", tool_name: "Bash",
                                       tool_input: { command: })
        answer.out && json(answer)["hookSpecificOutput"]
    end

    def test_hand_writes_are_refused
        WRITES.each do |command|
            out = decision(command)

            refute_nil out, command
            assert_equal "deny", out["permissionDecision"]
            assert_match "`bin/ledger show ADDRESS`",
                         out["permissionDecisionReason"]
        end
    end

    def test_reads_and_the_launcher_pass
        PASSES.each { assert_nil decision(it), it }
    end

    def test_the_default_journal_is_the_journals_own
        assert_equal Ledger::Journal::DEFAULT,
                     Ledger::Hooks::JournalName::DEFAULT
    end
end
