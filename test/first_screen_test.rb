# frozen_string_literal: true

require "test_helper"
require_relative "support/ledger_fixture"

# What a ledger page puts first: the head keeps the name, the goal's
# line, the next step and the tiles, the settings folded under Details;
# the criteria not met follow the Goal; a blocked piece says its cause
# under its title; a planned or deferred piece with nothing to say is
# one row opening into its card.
class FirstScreenTest < ViewerTest
    include LedgerFixture

    ROUTE = ["--route", "sonnet, effort: low"].freeze

    def build_fixture
        super
        ledger("criterion", "new", "--text", "the parser passes its suite")
        ledger("piece", "new", *ROUTE, "--title", "write the lexer")
        ledger("piece", "new", *ROUTE, "--title", "write the parser",
               "--problem", "the grammar is open", "--plan", "settle it")
        ledger("piece", "new", *ROUTE, "--title", "write the printer")
        ledger("piece", "P3", "--status", "blocked",
               "--what", "blocked: the grammar is not settled")
        ledger("piece", "new", *ROUTE, "--title", "draw the tables")
        ledger("piece", "P4", "--status", "out", "--session", "s1")
    end

    def test_the_settings_fold_under_details_which_says_their_state
        head = page[%r{<header class="ledger-head">.*?</header>}m]
        fold = %r{<details class="ledger-details".*?</details></details>}m
        details = head[fold]

        assert_includes head, "<summary>Details: " \
                              '<span class="details-state">waker off</span>'
        assert_includes details, 'class="waker"'
        assert_includes details, '<details class="abandon-fold"'
        refute_match(/abandon-fold/, head.sub(details, ""))
        assert_operator head.index("next-step"), :<,
                        head.index("ledger-details")
    end

    def test_the_goals_line_sits_under_the_name
        assert_match(%r{<h1>gamma</h1><p class="goal-line">port the parser</p>},
                     page)
    end

    def test_the_criteria_follow_the_goal
        goal = page.index("</svg>Goal</h2>")
        criteria = page.index('<h2 id="criteria">')
        flight = page.index('<h2 id="flight">')

        assert_operator goal, :<, criteria
        assert_operator criteria, :<, flight
        between = page[goal...criteria]
        refute_match(/<h2/, between)
    end

    def test_a_blocked_piece_says_its_cause_under_its_title
        card = card("piece-P3")
        cause = card.index("the grammar is not settled")

        assert_operator cause, :<, card.index('class="raid"')
        refute_includes card, "What it covers"
    end

    def test_a_quiet_planned_piece_is_a_row_opening_into_its_card
        row = card("piece-P1")

        assert_includes page, %(<li class="is-flight is-row" id="piece-P1">)
        assert_includes row, %(<details class="piece-row" id="#{@lid}-row-P1">)
        assert_includes row, "<summary><span class=\"text\">write the lexer"
        assert_includes row, "Comment on P1 before it goes out"
        assert_includes row, "drop-fold"
    end

    def test_a_piece_with_something_to_say_stays_a_card
        %w[piece-P2 piece-P3 piece-P4].each do |anchor|
            refute_includes card(anchor), "is-row", anchor
            assert_includes card(anchor), "card-head", anchor
        end
    end

    # Returned, stalled or ready and not sent: the issue on the RAID line
    # is what to read, so the piece stays a card.
    def test_a_planned_piece_with_an_issue_stays_a_card
        ledger("piece", "P1", "--status", "out", "--session", "s1")
        ledger("piece", "P1", "--status", "planned", "--cause", "depth")
        card = card("piece-P1")

        assert_includes card, "card-head"
        refute_includes card, "piece-row"
        assert_includes card, "returned 1: depth"
    end

    private

    def page
        @page ||= begin
            sign_in
            https "/l/#{@lid}"
            last_response.body
        end
    end

    # The card or row whose id is ANCHOR, to its closing tag's start.
    def card(anchor)
        from = page.index(%(id="#{anchor}")) or flunk("no #{anchor}")
        page[from...page.index("</li>", from)]
    end
end
