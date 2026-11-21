# frozen_string_literal: true

require_relative "test_helper"

require "ledger_viewer/links_graph"
require "ledger_viewer/render/views"

# A JSON v1 document with every edge kind of the links page: X1 answers O1,
# replaces X0, rests on C1 and F1; X9 (the session's) led to O1; O1
# replaces O0; X1 led to P1, P2 and O2.
module LinksFixture
    WORDS = %(use sqlite, <b>not</b> files & "quotes")
    LINKS = [%w[answers X1 O1], %w[replaces X1 X0], %w[rests_on X1 C1],
             %w[rests_on X1 F1], %w[led_to X9 O1],
             %w[replaces O1 O0], %w[led_to X1 P1], %w[led_to X1 P2],
             %w[led_to X1 O2]].freeze
    CLOSED = "2026-11-20T10:00:00+01:00"

    module_function

    def item(id, **fields) = { id:, **fields }

    def document
        { schema: 1, kind: "ledger", ledger: { address: "/work/a/LEDGER.md" },
          decisions: decisions, facts: facts, pieces: pieces,
          constraints: [item("C1", text: "no legacy", quote: "no legacy mode")],
          questions: [item("O2", title: "Which port?", by: "P1")],
          closed_questions: [item("O0", title: "Files?"),
                             item("O1", title: "Which store?",
                                        closed_at: CLOSED)],
          links: LINKS.map { |kind, from, to| { kind:, from:, to: } } }
    end

    def decisions
        [item("X0", body: "keep markdown", by: "user", date: "2026-11-01"),
         item("X1", body: "O1: #{WORDS}", by: "user", date: "2026-11-20",
                    note: "after a long talk"),
         item("X9", body: "ask about the store", by: "me",
                    date: "2026-11-19")]
    end

    def facts = [item("F1", text: "sequel is vendored", pointer: "Gemfile")]

    def pieces
        [item("P1", title: "The journal", status: "verified", settled: true,
                    after: [], for: []),
         item("P2", title: "The viewer", status: "planned", settled: false,
                    after: ["P1"], for: ["D1"])]
    end
end

# The links page: the walk over a JSON v1 document, and the view it draws.
class LinksGraphTest < Minitest::Test
    GRAPH = LedgerViewer::LinksGraph
    FIXTURE = LinksFixture

    def view(id) = GRAPH.call(FIXTURE.document, id)

    # [id, via, [children]] for a whole tree.
    def shape(nodes)
        nodes.map { [it.id, it.via, shape(it.next_nodes)] }
    end

    def test_a_piece_goes_back_to_the_decision_and_the_words
        assert_equal [["X1", "led to it",
                       [["O1", "was answered by it",
                         [["X9", "led to it", []],
                          ["O0", "was replaced by it", []]]],
                        ["X0", "was replaced by it", []],
                        ["C1", "is relied on by it", []],
                        ["F1", "is relied on by it", []]]]],
                     shape(view("P1").back)
    end

    def test_a_decision_goes_forward_to_what_it_led_to
        assert_equal [["P1", "led to", []], ["P2", "led to", []],
                      ["O2", "led to", []]], shape(view("X1").forward)
    end

    def test_a_forward_walk_follows_the_answer_and_the_replacement
        assert_equal [["O1", "led to", [["X1", "answered by", forward_x1],
                                        ["O2", "replaced by",
                                         [["X8", "answered by", []]]]]]],
                     shape(GRAPH.call(longer, "X9").forward)
    end

    # O2 replaces O1, and a user decision X8 answers O2.
    def longer
        doc = FIXTURE.document
        x8 = FIXTURE.item("X8", body: "O2: 4580", by: "user",
                                date: "2026-11-21")
        links = doc[:links] + [{ kind: "replaces", from: "O2", to: "O1" },
                               { kind: "answers", from: "X8", to: "O2" }]
        doc.merge(links:, decisions: doc[:decisions] + [x8])
    end

    def forward_x1
        [["P1", "led to", []], ["P2", "led to", []],
         ["O2", "led to", [["X8", "answered by", []]]]]
    end

    def test_the_start_has_no_via_and_a_piece_has_nothing_forward
        found = view("P2")

        assert_nil found.start.via
        assert_empty found.forward
        assert_equal [["after", ["P1"]], ["serves", ["D1"]]], found.start.also
    end

    def test_the_nodes_say_whose_words_they_are
        back = view("P1").back.first.next_nodes.to_h { [it.id, it] }

        found = back["X0"].then { [it.text, it.user_words] }

        assert_equal ["keep markdown", true], found
        assert_equal "no legacy mode", back["C1"].quote
    end

    def test_the_session_s_own_decision_is_a_root_without_the_user_s_words
        o1 = view("P1").back.first.next_nodes.first
        x9 = o1.next_nodes.first

        refute x9.user_words
        assert x9.root?
        assert_equal "is-done", o1.state
    end

    def test_an_open_question_is_asked_and_a_question_names_its_preparer
        o2 = view("X1").forward.last

        assert_equal "is-ask", o2.state
        assert_equal [["prepared by", ["P1"]]], o2.also
    end

    def test_a_piece_state_follows_its_status
        assert_equal "is-done", view("X1").forward.first.state
        assert_nil view("X1").forward[1].state
    end

    def test_only_a_piece_or_a_decision_has_a_page
        %w[O1 F1 C1 D1 N1].each do |id|
            assert_raises(GRAPH::NotStartable) { view(id) }
        end
    end

    def test_an_id_the_ledger_does_not_hold_is_refused
        %w[P99 X7].each do |id|
            assert_raises(GRAPH::Unknown) { view(id) }
        end
    end

    def test_a_parsed_document_gives_the_same_view
        text = JSON.parse(JSON.generate(FIXTURE.document))

        assert_equal view("P1"), GRAPH.call(text, "P1")
    end
end

# The page drawn from the view: the words, the links, the browser file.
class LinksPageTest < Minitest::Test
    ROOT = File.expand_path("..", __dir__)
    HREF = ->(found) { "/links/#{found}" if found.match?(/\A[PX]/) }

    def render(id, href: HREF)
        views = LedgerViewer::Render::Views.new(File.join(ROOT, "views"))
        view = LedgerViewer::LinksGraph.call(LinksFixture.document, id)
        views.render("ledger/links", LedgerViewer::Render::Scope.new(views),
                     { view:, href: })
    end

    def test_the_page_shows_the_words_verbatim_and_escaped
        html = render("P1")

        assert_includes html, "use sqlite, &lt;b&gt;not&lt;/b&gt; " \
                              "files &amp; &quot;quotes&quot;"
        assert_includes html, "<q>no legacy mode</q>"
        refute_includes html, "<b>"
    end

    def test_the_page_says_whose_call_it_was
        html = render("P1")

        assert_includes html, "The session's call"
        assert_includes html, "Your words"
    end

    def test_a_piece_and_a_decision_are_links_and_a_fact_is_not
        html = render("P1")

        assert_includes html, %(href="/links/X1")
        refute_match(%r{href="/links/[FCO]}, html)
    end

    def test_an_empty_side_says_so
        assert_includes render("P2"), "Nothing is linked after P2."
    end

    def test_the_page_is_written_for_the_browser_check
        out = ENV.fetch("LINKS_HTML", nil)
        skip "LINKS_HTML names the file the browser check reads" unless out

        css = File.read(File.join(ROOT, "public/viewer.css"))
        mine = File.read(File.join(ROOT, "public/links.css"))
        File.write(out, <<~HTML)
            <!doctype html><html lang="en"><meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>links</title><style>#{css}</style><style>#{mine}</style>
            <body><main>#{render("P1")}#{render("X1")}</main></body></html>
        HTML
    end
end
