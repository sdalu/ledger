# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"

# The one word for the pieces that await the same words: a form per set
# of two or more, and no lone Merge, Push or Deploy on a piece that
# still awaits its commit.
class GiveAllTest < ViewerTest
    include LedgerFixture

    PIECE = ["--route", "sonnet, effort: low", "--problem", "p",
             "--risk", "2/10 — none", "--plan", "go",
             "--no-picture", "a rename"].freeze
    DONE = ["--status", "verified", "--verified-by", "me",
            "--evidence", "ok"].freeze

    TITLES = ["fix the reorder", "fix the header", "fix the footer",
              "fix the menu", "fix the search"].freeze

    # Pieces P1, P2, ... with the words each awaits, in this order.
    def build_fixture
        ledger("new", *GOAL)
        sets.each_with_index do |words, number|
            status = words.start_with?("start") ? [] : DONE
            ledger("piece", "new", *PIECE, *status,
                   "--title", TITLES.fetch(number))
            ledger("piece", "P#{number + 1}", "--awaits", words)
        end
    end

    def sets = []

    def page
        sign_in
        https "/l/#{@lid}"
        last_response.body
    end

    def forms(body) = body.scan(%r{<form class="give-all".*?</form>}m)

    def refs(form) = form[/name="refs" value="([^"]*)"/, 1]

    # The ids the group's chips link to, in order.
    def line(form)
        refs = form[%r{<p class="give-all-refs">.*?</p>}m]
        refs.scan(/<a class="id-link" href="#p-(P\d+)"/).flatten.join(" ")
    end

    # The tooltip text after the chip that links to `id`.
    def tip(form, id)
        form[%r{href="#p-#{id}".*?<span class="tip"[^>]*>(.*?)</span>}m, 1]
    end

    def buttons(body, id)
        card = body[%r{<li[^>]*id="p-#{id}".*?</li>}m]
        card.scan(/name="word" value="([^"]*)"/).flatten - ["drop"]
    end
end

class TwoGroupsTest < GiveAllTest
    def sets
        ["commit,merge", "start", "commit, merge", "start", "deploy"]
    end

    def test_two_sets_of_two_give_two_forms_in_the_page_order
        found = forms(page)

        assert_equal(["P1 P3", "P2 P4"], found.map { refs(it) })
        assert_includes found[0], "Commit + Merge all 2"
        assert_includes found[1], "Start all 2"
        assert_equal "P1 P3", line(found[0])
    end

    def test_a_singleton_set_has_no_form
        refute(forms(page).any? { refs(it).split.include?("P5") })
    end

    def test_a_group_short_of_all_does_not_say_all
        refute_includes forms(page).first, "All "
    end
end

class OtherSetTest < GiveAllTest
    def sets = ["other (a)", "other (a)", "start", "start"]

    def test_pieces_awaiting_other_are_not_grouped
        assert_equal(["P3 P4"], forms(page).map { refs(it) })
    end
end

class WholeTest < GiveAllTest
    def sets = %w[start start]

    def test_one_group_of_all_reads_as_all_with_its_line
        form = forms(page).first

        assert_includes form, "All 2 await the same words: start"
        assert_equal "P1 P2", line(form)
    end
end

class ChipTipTest < GiveAllTest
    def sets = %w[start start]

    def test_each_chip_tells_title_risk_and_plan
        form = forms(page).first

        assert_equal "fix the reorder · risk 2/10 · plan: go", tip(form, "P1")
        assert_equal "fix the header · risk 2/10 · plan: go", tip(form, "P2")
    end

    def test_a_long_plan_line_is_cut_at_eighty
        plan = "a" * 120
        line = LedgerViewer::Render::Groups.first_line("\n#{plan}\nmore")

        assert_equal 80, line.length
        assert line.end_with?("…")
    end
end

class SingleWordsTest < GiveAllTest
    def sets = ["commit,merge", "merge", "commit,deploy", "commit,push"]

    def test_a_piece_awaiting_commit_and_merge_has_no_lone_merge
        assert_equal ["commit, merge", "commit"], buttons(page, "P1")
    end

    def test_a_piece_awaiting_only_merge_keeps_merge
        assert_equal ["merge"], buttons(page, "P2")
    end

    def test_commit_and_deploy_has_no_lone_deploy_or_push
        body = page

        assert_equal ["commit, deploy", "commit"], buttons(body, "P3")
        assert_equal ["commit, push", "commit"], buttons(body, "P4")
    end
end
