# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"

# The page's Goal section: every block not done open, newest first, each
# headed by its G<n> chip; the done ones folded under "Done goals · N",
# newest first, each with its evidence.
class GoalSectionTest < ViewerTest
    include LedgerFixture

    def build_fixture
        super
        %w[second third fourth].each do |word|
            ledger("goal", "--quote", "now do the #{word} thing too",
                   "--title", "The #{word} thing", "--short", "the #{word}",
                   "--date", "2026-11-20")
        end
        ledger("goal", "G2", "--done", "the second shipped")
        ledger("goal", "G4", "--done", "the fourth shipped")
    end

    def test_active_blocks_come_first_newest_first_each_with_its_chip
        active, = section.split('<details class="goal-done"')

        assert_equal %w[3 1], chips(active)
        assert_equal ["The third thing", "Port the parser"],
                     active.scan(%r{<p class="goal-title">([^<]*)</p>})
                           .flatten
        refute_includes active, "Done:"
    end

    def test_done_blocks_fold_newest_first_with_their_evidence
        _, done = section.split('<details class="goal-done"')

        assert_includes done, "<summary>Done goals · 2</summary>"
        assert_equal %w[4 2], chips(done)
        assert_operator done.index("Done: the fourth shipped"), :<,
                        done.index("Done: the second shipped")
    end

    def test_the_words_fold_of_the_newest_active_block_keeps_its_id
        assert_equal 1, section.scan(%(id="#{@lid}-goal-words")).size
        assert_equal 4, section.scan('<details class="goal-words"').size
        assert_match(/goal-title">The third thing.*?id="#{@lid}-goal-words"/,
                     section)
    end

    def test_without_a_done_block_there_is_no_fold
        ledger("goal", "G2", "--undone")
        ledger("goal", "G4", "--undone")

        refute_includes section, "goal-done"
        assert_equal %w[4 3 2 1], chips(section)
    end

    private

    # The page's Goal section, from its heading to the note's fold.
    def section
        sign_in
        https "/l/#{@lid}"
        body = last_response.body
        body[(body.index('<div class="ledger-main">')...
              body.index('<details class="comment-fold note-fold"'))]
    end

    # The numbers of the G chips in HTML, in order.
    def chips(html)
        html.scan(%r{<span class="l">G</span><span class="n">(\d+)</span>})
            .flatten
    end
end
