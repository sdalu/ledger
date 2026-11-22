# frozen_string_literal: true

require_relative "purge_case"

# `purge`: what it refuses and what a dry run says; it writes nothing
# until --confirmed.
class PurgeTest < PurgeCase
    def test_a_dry_run_lists_the_counts_and_writes_nothing
        before = kept
        code, out, err = cli("purge", "L#{@beta}")
        assert_equal 2, code
        assert_includes out, "would remove L#{@beta}: /work/beta, closed "
        assert_includes out, "  pieces: 1"
        assert_includes out, "  events: #{@beta_counts[:events]}"
        assert_includes err, "--confirmed"
        assert_equal before, kept
        assert_empty backups
    end

    def test_a_live_ledger_is_refused
        ok("new", "/work/live/LEDGER.md", *GOAL)
        id = db[:ledgers].where(place: "/work/live").get(:id)
        before = kept
        code, _out, err = cli("purge", "L#{id}", "--confirmed")
        assert_equal 2, code
        assert_includes err, "L#{id} is live"
        assert_equal before, kept
        assert_empty backups
    end

    def test_an_unknown_id_is_refused
        before = kept
        code, _out, err = cli("purge", "L999", "--confirmed")
        assert_equal 2, code
        assert_includes err, "no ledger L999"
        assert_equal before, kept
        assert_empty backups
    end

    def test_a_word_that_is_not_an_id_is_refused
        code, _out, err = cli("purge", BETA, "--confirmed")
        assert_equal 2, code
        assert_includes err, "is not a ledger id"
    end

    def test_an_existing_backup_name_is_refused
        now = Time.new(2026, 11, 22, 10, 0, 0)
        name = Ledger::Backup.purge_path(@journal.path, @beta, at: now)
        File.write(name, "mine")
        before = kept
        code, _out, err = at(now) { cli("purge", "L#{@beta}", "--confirmed") }
        assert_equal 2, code
        assert_includes err, "exists; nothing removed"
        assert_equal "mine", File.read(name)
        assert_equal before, kept
    end

    def test_the_help_says_it_is_irreversible
        out = ok("help", "purge")
        assert_includes out, "irreversible"
        assert_includes out, "the id `close` prints"
    end

    # The block run with Time.now fixed at TIME.
    def at(time)
        Time.singleton_class.alias_method(:real_now, :now)
        Time.define_singleton_method(:now) { time }
        yield
    ensure
        Time.singleton_class.alias_method(:now, :real_now)
        Time.singleton_class.remove_method(:real_now)
    end
end
