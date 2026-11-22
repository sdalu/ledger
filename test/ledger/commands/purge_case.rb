# frozen_string_literal: true

require_relative "helper"

# What the `purge` tests share: two closed ledgers, BETA and GAMMA, each
# with a row in every table a ledger reaches; BETA also with the child
# rows no command leaves once abandoned, so every table is exercised.
class PurgeCase < CommandCase
    GAMMA = "/work/gamma/LEDGER.md"
    PNG = "\x89PNG\r\n\x00\xFF".b
    PIECE = ["new", "--title", "Build the parser", "--route",
             "sonnet, effort: low", "--problem", "p", "--risk", "2/10 — r",
             "--no-picture", "w", "--for", "D1"].freeze
    QUESTION = ["Which?", "--title", "Which one", "--problem", "p", "--risk",
                "2/10 — r", "--choices", "A = one | B = two", "--recommend",
                "A, simple", "--no-picture", "w"].freeze
    # Child rows written straight; a symbol names the id of that owner.
    LEFTOVERS = {
        piece_awaits: { piece_id: :piece, position: 1, word: "start" },
        piece_criteria: { piece_id: :piece, position: 1, text: "c",
                          mark: " " },
        piece_scopes: { piece_id: :piece, position: 1, word: "w", text: "t" },
        piece_commits: { piece_id: :piece, position: 1, sha: "a1b2c3d" },
        piece_gates: { piece_id: :piece, event_id: :event, name: "unit",
                       state: "passed" },
        piece_reports: { piece_id: :piece, event_id: :event, status: "DONE" },
        piece_briefs: { piece_id: :piece, version: 1, text: "b",
                        event_id: :event },
        piece_pictures: { piece_id: :piece, position: 1, role: "before",
                          name: "n" },
        assumption_links: { assumption_id: :assumption, piece_id: :piece },
        assumption_sees: { assumption_id: :assumption, position: 1,
                           criterion_id: :criterion },
        question_items: { question_id: :question, position: 1, text: "i" },
        question_sees: { question_id: :question, position: 1,
                         piece_id: :piece },
        piece_assessments: { ledger_id: :ledger, piece_id: :piece,
                             event_id: :event, what: "w", why: "y",
                             model: "sonnet", risk_text: "r", mode: "m",
                             mode_attended: true, block: "b" }
    }.freeze

    OWNERS = { piece: :pieces, question: :questions,
               assumption: :assumptions, event: :events,
               criterion: :criteria }.freeze

    def setup
        super
        ok("new", GAMMA, *GOAL)
        @gamma = db[:ledgers].where(place: "/work/gamma").get(:id)
        populate(BETA)
        leftovers(@beta)
        populate(GAMMA)
        @beta_counts = counts(@beta)
        @gamma_counts = counts(@gamma)
    end

    def populate(address)
        id = db[:ledgers].where(place: File.dirname(address)).get(:id)
        items(address)
        question(address)
        piece(address)
        waker(id)
        ok("close", address, "--abandon", "--take", "N1")
    end

    def items(address)
        ok("fact", address, "a — b")
        ok("assume", address, "x holds — check it")
        ok("constraint", address, "never — here", "--where", "there")
        ok("decide", address, "go", "--by", "me")
        ok("noticed", address, "a thing")
        Ledger::Inbox.append(@journal, address, [{ "text" => "hi" }],
                             actor: "cli")
    end

    # O1 shows two pictures: the PNG both ledgers place, one blob in the
    # journal, and one of the ledger's own bytes.
    def question(address)
        ok("ask", address, *QUESTION)
        stem = File.join(@dir, File.dirname(address).tr("/", "_"))
        File.binwrite("#{stem}.png", PNG)
        File.binwrite("#{stem}-own.png", PNG + address.b)
        ok("mockup", address, "#{stem}.png", "#{stem}-own.png",
           "--question", "O1")
    end

    def piece(address)
        ok("piece", address, *PIECE)
        ok("piece", address, "P1", "--status", "out", "--session", "s1")
        ok("piece", address, "P1", "--status", "planned", "--cause", "env")
        ok("piece", address, "P1", "--awaits", "start")
    end

    def waker(id)
        db[:sessions].insert_conflict.insert(session_id: "s#{id}", cwd: "/w",
                                             at: 1)
        db[:session_ledgers].insert(session_id: "s#{id}", ledger_id: id)
        db[:wakes].insert(ledger_id: id, session_id: "s#{id}", at: 1,
                          path: "socket", outcome: "posted")
        db[:outcomes].insert(ledger_id: id, at: 1, kind: "refusal",
                             rule: "usage")
    end

    # Only on the ledger purged, so the other one's checks still pass.
    def leftovers(id)
        ids = OWNERS.transform_values { db[it].where(ledger_id: id).get(:id) }
                    .merge(ledger: id)
        LEFTOVERS.each do |table, row|
            db[table].insert(row.transform_values { ids.fetch(it, it) })
        end
    end

    def counts(id) = Ledger::Purge.new(db, id).counts

    def totals = db.tables.to_h { [it, db[it].count] }

    # The totals a refusal leaves alone: all but the outcome it records.
    def kept = totals.except(:outcomes)

    def backups = Dir.glob("#{@journal.path}.before-purge-*")
end
