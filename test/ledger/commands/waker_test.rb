# frozen_string_literal: true

require_relative "helper"

# `waker PATH on|off`: the switch, off by default, one event that undo
# takes back.
class WakerCommandTest < CommandCase
    def waker = db[:ledgers].where(id: @beta).get(:waker)

    def test_a_ledger_starts_switched_off
        refute waker
    end

    def test_on_then_off_each_write_one_event
        assert_includes ok("waker", BETA, "on"), "waker on: #{BETA}"
        assert waker
        assert_equal %w[waker ["on"]], events.last.values_at(:command, :argv)

        ok("waker", BETA, "off")

        refute waker
    end

    def test_undo_takes_the_switch_back
        ok("waker", BETA, "on")
        ok("undo", BETA)

        refute waker
    end

    def test_a_word_but_on_or_off_is_refused
        assert_refused("waker", BETA, "maybe", "on or off, not \"maybe\"")
    end

    def test_the_word_is_in_the_help
        assert_includes ok("help"), "waker PATH on|off"
    end
end
