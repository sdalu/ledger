# frozen_string_literal: true

require_relative "helper"

# `edit PATH A<n> --text`: an assumption's words, its check staying.
class EditAssumptionTest < CommandCase
    def test_an_assumption_is_reworded_and_keeps_its_check
        ok("assume", BETA, "port 80 is free — ss -ltn")
        out = ok("edit", BETA, "A1", "--text", "port 81 is free")
        assert_equal "- A1 [open] port 81 is free — check: ss -ltn",
                     out.lines.first.chomp
        assert_equal "ss -ltn", db[:assumptions].get(:check)
    end

    def test_an_assumption_edit_is_undone
        ok("assume", BETA, "port 80 is free — ss -ltn")
        ok("edit", BETA, "A1", "--text", "port 81 is free")
        ok("undo", BETA)
        assert_equal "port 80 is free", db[:assumptions].get(:text)
    end

    def test_an_unknown_assumption_is_refused
        assert_refused("edit", BETA, "A9", "--text", "x")
    end
end
