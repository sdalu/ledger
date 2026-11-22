# frozen_string_literal: true

require_relative "helper"

require "ledger/read"

# A ledger with one of every kind of row, written at fixed times, the
# fixture of the JSON and Read tests.
class JsonCase < RenderTest
    T0 = 1_700_000_000_000
    MINUTE = 60_000
    NOW = T0 + (200 * MINUTE)

    def setup
        super
        @zone = ENV.fetch("TZ", nil)
        ENV["TZ"] = "Etc/GMT-1"
    end

    def teardown
        ENV["TZ"] = @zone
        super
    end

    def document = Ledger::Read.ledger(@journal, ADDRESS, now: NOW)

    # The fixture, in three writes: the rows, then a claim and a take.
    def build
        write("import", [], at: T0) { rows(it) }
        write("take", [], at: T0 + MINUTE, actor: "viewer:ann") do |change|
            take(change)
        end
        write("out", [], at: T0 + (2 * MINUTE)) do |change|
            claim(change, "s1")
        end
    end

    def rows(change)
        goal(change, title: "Ledger in Ruby", short: "one journal")
        criterion(change, mark: "x", evidence: "seen")
        change.insert(:constraints, n: change.next_id("C"), text: "no legacy",
                                    quote: "no legacy mode")
        change.insert(:facts, n: change.next_id("F"), text: "sqlite",
                              pointer: "journal.rb")
        pieces(change)
        questions(change)
        more(change)
    end

    def more(change)
        change.insert(:noticed, line: "- a stray file")
        change.insert(:inbox_entries, n: change.next_id("N"),
                                      at: "2026-11-20 10:00:00", ref: "O1",
                                      payload: '{"ref":"O1"}')
    end

    def pieces(change)
        piece(change, status: "verified", evidence: "ran", skills: "ruby",
                      risk: "3/10 — small", risk_rating: 3, plan: "in order")
        two = piece(change, status: "planned", problem: "slow")
        planned_rows(change, two)
        # Planned here, out once the third write claims it.
        piece(change, model: nil, effort: nil, peer: "Skills:x")
    end

    def planned_rows(change, two)
        change.insert(:piece_links, piece_id: two, kind: "after", position: 0,
                                    after_id: 1)
        change.insert(:piece_links, piece_id: two, kind: "for", position: 1,
                                    criterion_id: 1)
        change.insert(:piece_awaits, piece_id: two, position: 0, word: "commit")
        change.insert(:piece_scopes, piece_id: two, position: 0, word: "edit",
                                     text: "lib/")
        change.insert(:piece_briefs, piece_id: two, version: 1, text: "b")
        change.insert(:piece_criteria, piece_id: two, position: 0, text: "t",
                                       mark: " ")
    end

    def questions(change)
        pending = question(change, by_id: 3, risk: "5/10 — mid",
                                   risk_rating: 5, recommend: "A")
        question_rows(change, pending)
        question(change, closed_at: T0 + 5)
        decision(change)
    end

    def question_rows(change, pending)
        change.insert(:question_choices, question_id: pending, position: 0,
                                         label: "A", effect: "go", cost: "slow")
        change.insert(:question_items, question_id: pending, position: 0,
                                       text: "one")
        change.insert(:question_sees, question_id: pending, position: 0,
                                      fact_id: 1)
        change.insert(:question_pictures, question_id: pending, position: 0,
                                          name: "pic")
        change.insert(:pictures, name: "pic", path: "", type: "image/png",
                                 bytes: Sequel.blob("12345"))
    end

    def decision(change)
        x = change.insert(:decisions, n: change.next_id("X"),
                                      date: "2026-11-20", body: "O2: yes",
                                      by: "user", subject: "O2")
        change.insert(:links, kind: "answers", from_kind: "X", from_row: x,
                              to_kind: "O", to_row: 2)
    end

    def take(change)
        change.update(:inbox_entries, 1, taken_id: change.event_id)
    end

    def claim(change, session)
        change.update(:pieces, 3, status: "out", claimed_by: session)
    end

    # A planned, routed piece, verified by me when verified; returns its
    # row id.
    def piece(change, **columns)
        n = change.next_id("P")
        by = "me" if columns[:status] == "verified"
        change.insert(:pieces, n:, status: "planned", model: "sonnet",
                               effort: "low", dash: false,
                               title: "Piece #{n}", verified_by: by,
                               **columns)
    end
end

# The document's shape: the keys in the note's order, the rows as
# values, derived states from Derive.
class JsonTest < JsonCase
    TOP = %i[schema kind ledger goals criteria constraints facts assumptions
             decisions links closed_questions pictures pieces questions refs
             noticed inbox asked status fails].freeze
    PIECE = %i[id status kept_reason until route route_text title detail
               done_when evidence commits after for awaits scope
               rests_on_assumptions
               problem risk plan verified_by claim irreversible step_risk
               work_risk ready ready_since unsent
               stalled touched_at settled brief criteria returns assessments
               gates report pictures no_picture picture_pending builds
               obsoleted_by line].freeze
    QUESTION = %i[id title detail problem risk recommend choices items by see
                  pictures rests_on_assumptions preparing preparing_status
                  held_by asked_since line].freeze

    EMPTY = {
        schema: 1, kind: "ledger",
        ledger: { id: 1, address: "/work/alpha/LEDGER.md",
                  place: "/work/alpha", name: "", project: "alpha",
                  url_id: "e1cd342a1d", updated_at: "2023-11-14T23:13:20+01:00",
                  closed_at: nil },
        goals: [{ id: "G1", stamp: "2026-11-19, verbatim",
                  date: "2026-11-19", revised: false, title: nil, short: nil,
                  context: nil, quote: "the user's words", done: false,
                  done_evidence: nil }],
        criteria: [], constraints: [], facts: [], assumptions: [],
        decisions: [], links: [],
        closed_questions: [], pictures: [], pieces: [], questions: [],
        refs: {}, noticed: [], inbox: [], asked: {},
        status: "Status (/work/alpha/LEDGER.md) — criteria 0/0 · " \
                "pieces 0/0 verified",
        fails: []
    }.freeze

    def test_an_empty_ledger_is_one_whole_document
        write("import", [], at: T0) { goal(it) }
        failures = Ledger::Checks.failures(Ledger::Snapshot.read(db, 1))
        fails = failures.map { |name, detail| { name:, detail: } }

        assert_equal EMPTY.merge(fails:), document
    end

    def test_schema_then_kind_then_the_notes_keys_in_order
        build

        assert_equal TOP, document.keys
        assert_equal [1, "ledger"], document.values.first(2)
    end

    def test_every_piece_and_question_has_its_keys_in_order
        build

        assert_equal [PIECE] * 3, document[:pieces].map(&:keys)
        assert_equal [QUESTION], document[:questions].map(&:keys)
        assert_equal [*QUESTION, :closed_at],
                     document[:closed_questions].first.keys
    end

    def test_two_reads_of_one_state_are_equal_and_serialise_alike
        build
        first = Ledger::Render::Json.generate(document)

        assert_equal first, Ledger::Render::Json.generate(document)
    end

    def test_times_are_iso_8601_in_local_time_with_the_offset
        build
        header = document[:ledger]

        assert_equal "2023-11-14T23:15:20+01:00", header[:updated_at]
        ENV["TZ"] = "Etc/GMT+5"

        assert_equal "2023-11-14T17:15:20-05:00", document[:ledger][:updated_at]
    end

    def test_the_ledger_header_names_the_address_and_the_url_id
        build

        assert_equal "e1cd342a1d",
                     Digest::SHA1.hexdigest(ADDRESS)[0, 10]
        assert_equal({ id: @ledger[:id], address: ADDRESS,
                       place: "/work/alpha", name: "", project: "alpha",
                       url_id: "e1cd342a1d",
                       updated_at: "2023-11-14T23:15:20+01:00",
                       closed_at: nil }, document[:ledger])
    end
end

# The rows as values, section by section.
class JsonRowsTest < JsonCase
    def test_decisions_have_x_ids_and_links_name_visible_ids_both_ends
        build

        assert_equal "X1", document[:decisions].first[:id]
        assert_equal [{ kind: "answers", from: "X1", to: "O2" }],
                     document[:links]
    end

    def test_refs_hold_c_d_f_p_and_x_with_the_line
        build

        assert_equal %w[C1 D1 F1 P1 P2 P3 X1], document[:refs].keys
        assert_equal({ kind: "X", line: "- 2026-11-20 — O2: yes — by user" },
                     document[:refs]["X1"])
    end

    def test_closed_questions_are_apart_and_carry_their_closing_time
        build
        closed = document[:closed_questions]

        assert_equal(%w[O2], closed.map { it[:id] })
        assert_equal "2023-11-14T23:13:20+01:00", closed.first[:closed_at]
        assert_equal(%w[O1], document[:questions].map { it[:id] })
    end

    def test_pictures_carry_their_sizes_and_never_their_bytes
        build

        assert_equal [{ name: "pic", files: [{ path: "", type: "image/png",
                                               size: 5 }] }],
                     document[:pictures]
        refute_includes Ledger::Render::Json.generate(document), "12345"
    end

    # P2 awaits commit: not ready.
    def test_pieces_take_ready_stalled_and_settled_from_derive
        build
        states = document[:pieces].map do |piece|
            piece.values_at(:ready, :unsent, :stalled, :settled)
        end

        assert_equal [[false, false, false, true],
                      [false, false, false, false],
                      [false, false, true, false]], states
    end

    def test_a_piece_carries_its_route_and_risk
        build
        one, _, three = document[:pieces]

        assert_equal "sonnet, effort: low, skills: ruby", one[:route_text]
        assert_equal({ rating: 3, text: "3/10 — small" }, one[:risk])
        assert_equal({ model: nil, effort: nil, skills: nil,
                       peer: "Skills:x" }, three[:route])
    end

    def test_a_deferred_piece_carries_its_condition
        write("import") { piece(it, status: "deferred", until: "later") }

        assert_equal %w[deferred later],
                     document[:pieces].first.values_at(:status, :until)
    end

    def test_a_piece_carries_its_links_brief_and_criteria
        build
        two = document[:pieces][1]

        assert_equal [%w[P1], %w[D1], [{ word: "commit", what: "" }],
                      [{ word: "edit", text: "lib/" }]],
                     two.values_at(:after, :for, :awaits, :scope)
        assert_equal({ version: 1, at: "2023-11-14T23:13:20+01:00" },
                     two[:brief])
        assert_equal [{ text: "t", mark: " ", evidence: nil }],
                     two[:criteria]
    end

    def test_a_claim_is_the_session_and_the_time_it_took_the_piece
        build

        assert_equal({ session: "s1", since: "2023-11-14T23:15:20+01:00" },
                     document[:pieces][2][:claim])
        assert_nil document[:pieces][0][:claim]
    end

    def test_a_question_carries_its_choices_see_pictures_and_preparer
        build
        question = document[:questions].first

        assert_equal [{ label: "A", effect: "go", cost: "slow",
                        text: "A = go; slow" }], question[:choices]
        assert_equal [%w[F1], [{ name: "pic" }], "P3", "out", nil],
                     question.values_at(:see, :pictures, :preparing,
                                        :preparing_status, :asked_since)
    end

    def test_the_inbox_says_who_took_an_entry_and_when
        build

        assert_equal [{ id: "N1", at: "2026-11-20 10:00:00", ref: "O1",
                        payload: '{"ref":"O1"}', malformed: false,
                        taken: true, taken_at: "2023-11-14T23:14:20+01:00",
                        taken_by: "viewer:ann" }], document[:inbox]
    end

    def test_status_and_asked_are_derive_answers
        build
        derive = Ledger::Derive.read(db, Ledger::Snapshot.read(db, 1), now: NOW)

        assert_equal Ledger::Derive::StatusLine.new(derive).to_s,
                     document[:status]
        assert_equal({ "P2:commit" => "2023-11-14T23:13:20+01:00" },
                     document[:asked])
    end

    def test_fails_are_the_check_failures
        build
        failures = Ledger::Checks.failures(Ledger::Snapshot.read(db, 1))

        assert_equal failures.map { |name, detail| { name:, detail: } },
                     document[:fails]
    end

    def test_noticed_lines_pass_through
        build

        assert_equal ["- a stray file"], document[:noticed]
    end
end

# A fact's pointer and a constraint's where carry their kind.
class JsonPointerTest < JsonCase
    def test_a_pointer_and_a_where_carry_their_kind
        build
        fact = document[:facts].first
        constraint = document[:constraints].first

        assert_equal %i[id text pointer pointer_kind line], fact.keys
        assert_equal "path", fact[:pointer_kind]
        assert_equal %i[id text quote where where_kind line], constraint.keys
        assert_equal [nil, nil], constraint.values_at(:where, :where_kind)
    end
end

# A ready piece's time: P2 given its word back ten minutes in, so ready
# since then, and unsent at NOW.
class JsonReadyTest < JsonCase
    def test_a_ready_piece_says_since_when_and_whether_unsent
        build
        write("piece", [], at: T0 + (10 * MINUTE)) { unawait(it) }

        assert_equal [true, "2023-11-14T23:23:20+01:00", true],
                     document[:pieces][1].values_at(:ready, :ready_since,
                                                    :unsent)
    end

    def unawait(change)
        change.delete(:piece_scopes, db[:piece_scopes].get(:id))
        change.delete(:piece_awaits, db[:piece_awaits].get(:id))
    end
end
