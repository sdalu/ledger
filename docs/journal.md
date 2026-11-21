# The journal

Design note, as built, 2026-11-21. One machine-wide SQLite file holds
every ledger, its history and the viewer's sign-in state; `bin/ledger`
(Ruby, Sequel) is the one command, reached as `ledger` on PATH, and no
command writes a file beside the journal. `show` prints a ledger as
Markdown; that text is the command's own output, free to change.

Codes in the schema and the text: U1 the event log, U2 derived states, U3
sequential ids, U4 versioned JSON, U5 the resume view, U7 no task tools,
U10 briefs, U11 `verified_by`, U12 the claim, U14 stalled, U16 criteria
per piece (the upgrades taken from a survey of tracker tools, section
9); S1 pictures as blobs, S2 the stall budget.

Where this note says *decision*, the choice was the orchestrator's or
the user's and is recorded in the goal's ledger; one marked reviewable
may be revisited. The code is the authority: where the two disagree,
this note is the stale one.

The file: `~/.local/state/orchestration/journal.db`, mode 0600 in a
directory made 0700 (it holds sesam's password hashes); `LEDGER_JOURNAL`
names another file (tests, a sandbox). *Decision*: the variable's name.
WAL mode, `foreign_keys = ON`, `busy_timeout = 10000`, every write a
`BEGIN IMMEDIATE` transaction. SQLite is 3.53.4 here (measured
2026-11-20, `sqlite3 -version`): `RETURNING`, partial indexes, `CHECK`
and `STRICT` are all available.

## 1. Schema

Two migration sets in one file: sesam's own (`Sesam.migrate(db)`,
version table `sesam_schema`, run first, as sesam asks) and the
journal's (`Sequel::Migrator`, version table `ledger_schema`,
`lib/ledger/migrations/`). No journal table references sesam's; an
event names a viewer user as text, so deleting a user deletes no
history.

**Order is row order.** Items of one kind are shown in `id` order, which
is insertion order. No `position`
column, except inside lists on one line (links, choices, items, words).

**Ids.** An item's visible id is its kind letter and `n` (`P7`), unique
per ledger; references between items are foreign keys on row ids, so a
renumber changes one `n` and every structured reference follows. A
decision's id is `X<n>` (Links and view): given by the counter, shown by
`show ADDRESS X<n>`, the JSON and the viewer, never printed in the
Markdown. A Goal block has no visible id (see
`edit`, section 4); an `Out of scope, noticed` line has the id `Z<n>` of
its row, printed nowhere in the Markdown.

**Questions keep their row.** `answer` and `ask --replaces` set
`questions.closed_at` instead of deleting the row (*decision*): a link
`X<n>` answers `O<n>` needs its target, and the graph page walks from a
piece back through the question to the user's words. `show` prints
under Open the rows whose `closed_at` is NULL; every derived state and
check reads those alone.

**Text classes.** `V` columns hold the user's words verbatim; `P`
columns hold the session's prose as given. Neither is ever reparsed:
whatever a check or a hook needs from a line is split out into its own
column by the writer once, when the row is written.

```ruby
# frozen_string_literal: true

# lib/ledger/migrations/001_journal.rb (sketch: names, types, keys)
Sequel.migration do
    change do
        create_table(:ledgers) do
            primary_key :id
            String :place, null: false   # absolute dir the address names
            String :name, null: false, default: ""  # "" or "x" (LEDGER-x)
            String :project, null: false # project_name(), self-routed
            Bignum :created_at, null: false          # ms since the epoch
            Bignum :closed_at
            String :beat_line            # the stall counter: the last status line
            Integer :beat_count, null: false, default: 0
            index %i[place name], unique: true, where: { closed_at: nil }
        end
        create_table(:counters) do       # U3: the last n given, per kind
            foreign_key :ledger_id, :ledgers, null: false
            String :kind, null: false    # P O D C F N X
            Integer :last, null: false, default: 0
            primary_key %i[ledger_id kind]
        end
        create_table(:events) do         # U1: the write path
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            Bignum :at, null: false
            String :actor, null: false   # session:<id> | cli | viewer:<user>
            String :command, null: false # piece, ask, take, undo, inbox, …
            String :argv, null: false    # JSON array, as given
            String :summary              # the line the command printed
            foreign_key :undoes, :events # undo: the event; restore: the target
            index %i[ledger_id id]
        end
        create_table(:event_rows) do     # what one event changed
            foreign_key :event_id, :events, null: false
            String :tbl, null: false
            Integer :row_id, null: false
            String :before               # JSON row; nil: inserted
            String :after                # JSON row; nil: deleted
            index %i[tbl row_id]
        end
        create_table(:goals) do
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            String :stamp, null: false   # P, inside the label's "(…)", no parentheses
            String :date, null: false    # YYYY-MM-DD, from the stamp
            TrueClass :revised, null: false
            String :title                # P; NULL or non-empty
            String :short                # P; NULL or non-empty
            String :context              # P; NULL or non-empty
            String :quote, null: false   # V; lines without "> ", non-empty
        end
        create_table(:criteria) do       # Done when
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            Integer :n, null: false
            String :mark, null: false    # " " | "x" | "-"
            String :text, null: false    # P
            String :evidence             # P; "" = an empty "— evidence:"
            String :why                  # P
            unique %i[ledger_id n]
        end
        create_table(:constraints) do
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            Integer :n, null: false
            String :text, null: false    # V: the line after "C<n>: "
            String :quote, null: false   # V: the words a brief must carry
            unique %i[ledger_id n]
        end
        create_table(:facts) do
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            Integer :n, null: false
            String :text, null: false    # P
            String :pointer, null: false # P, non-empty
            unique %i[ledger_id n]
        end
        create_table(:decisions) do
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            Integer :n, null: false      # X<n>, not printed in the Markdown
            String :date, null: false
            String :body, null: false    # V when by user (quotes the user)
            String :by, null: false      # "user" | "me"
            String :note                 # P, the "(…)" after by
            String :subject              # "O3" when the body opens "O3:"
            unique %i[ledger_id n]
        end
        create_table(:links) do          # Links and view: X and O edges
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            String :kind, null: false    # answers replaces rests_on led_to
            String :from_kind, null: false   # X | O
            Integer :from_row, null: false   # row id in that kind's table
            String :to_kind, null: false     # O X F C P
            Integer :to_row, null: false     # row id in that kind's table
            foreign_key :event_id, :events, null: false
            index %i[ledger_id from_kind from_row]
            index %i[ledger_id to_kind to_row]
        end
        create_table(:pieces) do
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            Integer :n, null: false
            String :status, null: false  # U2: the seven stored states
            String :kept_reason          # P, non-empty iff kept
            String :model                # haiku sonnet opus fable
            String :effort               # low medium high xhigh max
            String :skills               # "c, ruby"
            String :peer                 # peer: SESSION
            TrueClass :dash, null: false # an unrouted line wrote "— "
            String :title, null: false   # P
            String :detail               # P
            String :done_when            # P; NULL or non-empty
            String :evidence             # P
            String :problem              # P
            String :risk                 # P, "7/10 — …" as written
            Integer :risk_rating         # 0..10, split out at write
            String :plan                 # P
            String :after_tail           # P, prose after the after: ids
            String :for_tail             # P, prose after the for: ids
            String :verified_by          # U11: "me", a route, peer: X
            String :claimed_by           # U12: session id while out
            unique %i[ledger_id n]
            index %i[ledger_id status]
        end
        create_table(:piece_links) do    # — after: / — for:
            primary_key :id
            foreign_key :piece_id, :pieces, null: false
            String :kind, null: false    # "after" | "for"
            Integer :position, null: false
            foreign_key :after_id, :pieces
            foreign_key :criterion_id, :criteria
        end
        create_table(:piece_awaits) do   # — awaits: one row per word
            primary_key :id
            foreign_key :piece_id, :pieces, null: false
            Integer :position, null: false
            String :word, null: false    # start commit deploy push merge other
            String :what                 # P, other's "(…)"
        end
        create_table(:piece_scopes) do   # — scope: WORD = what | …
            primary_key :id
            foreign_key :piece_id, :pieces, null: false
            Integer :position, null: false
            String :word, null: false
            String :text, null: false    # P
        end
        create_table(:piece_briefs) do   # U10: no command writes it yet
            primary_key :id
            foreign_key :piece_id, :pieces, null: false
            Integer :version, null: false
            String :text, null: false    # P, the brief as sent
            foreign_key :event_id, :events, null: false
        end
        create_table(:piece_criteria) do # U16: no command writes it yet
            primary_key :id
            foreign_key :piece_id, :pieces, null: false
            Integer :position, null: false
            String :text, null: false    # P
            String :mark, null: false    # " " | "x" | "-"
            String :evidence             # P
        end
        create_table(:questions) do      # Open
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            Integer :n, null: false
            String :title, null: false   # P
            String :detail, null: false  # P, the question sentence
            String :problem              # P
            String :risk                 # P, as written
            Integer :risk_rating
            String :recommend            # P
            foreign_key :by_id, :pieces  # — by: P<n>
            String :no_picture           # P, --no-picture's why (not shown)
            String :tail                 # P, prose after a link's ids
            Bignum :closed_at            # NULL while under Open
            unique %i[ledger_id n]
            index %i[ledger_id closed_at]
        end
        create_table(:question_choices) do
            primary_key :id
            foreign_key :question_id, :questions, null: false
            Integer :position, null: false
            String :label, null: false   # P
            String :effect               # P
            String :cost                 # P
        end
        create_table(:question_items) do # — items: a | b
            primary_key :id
            foreign_key :question_id, :questions, null: false
            Integer :position, null: false
            String :text, null: false    # P
        end
        create_table(:question_sees) do  # — see: F2, C3
            primary_key :id
            foreign_key :question_id, :questions, null: false
            Integer :position, null: false
            foreign_key :constraint_id, :constraints
            foreign_key :criterion_id, :criteria
            foreign_key :fact_id, :facts
            foreign_key :piece_id, :pieces
        end
        create_table(:pictures) do       # S1: a mockup's files, as blobs
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            String :name, null: false    # the mockup's name (`mockup: NAME`)
            String :path, null: false    # "" for one file; else its path in the directory
            String :type, null: false    # the served content type (MOCKUP_TYPES)
            File :bytes, null: false     # the file, byte for byte
            foreign_key :event_id, :events, null: false   # the mockup command
            unique %i[ledger_id name path]
        end
        create_table(:question_pictures) do  # — mockup: NAME | pending (P<n>)
            primary_key :id
            foreign_key :question_id, :questions, null: false
            Integer :position, null: false
            String :name                 # a pictures.name of this ledger
            foreign_key :pending_id, :pieces
        end
        create_table(:noticed) do        # Out of scope, noticed
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            String :line, null: false    # P, the whole line verbatim
        end
        create_table(:inbox_entries) do  # what the viewer sends
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            Integer :n, null: false      # N<n>, a malformed line's too
            String :at, null: false      # the viewer's "YYYY-MM-DD HH:MM:SS"
            String :ref                  # O3, P4, "order", "close", NULL: not a key
            String :payload, null: false # V: the JSON object as written
            TrueClass :malformed, null: false, default: false
            foreign_key :taken_id, :events   # the take event
            unique %i[ledger_id n]
        end
    end
end
```

```ruby
# frozen_string_literal: true

# lib/ledger/migrations/002_piece_returns.rb (sketch)
Sequel.migration do
    change do
        create_table(:piece_returns) do  # piece --status planned --cause
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            foreign_key :piece_id, :pieces, null: false
            foreign_key :event_id, :events, null: false # the return's write
            String :from_status, null: false # out | back
            String :cause, null: false   # brief split depth contract env
            index %i[ledger_id piece_id]
        end
    end
end
```

**A piece's returns.** A piece out or back that goes back to planned
(a retry) says why: `piece P<n> --status planned --cause C` writes a
`piece_returns` row in the same event as the status, its time and actor
those of the event. The causes: `brief`, the brief lacked something;
`split`, the piece was cut wrong; `depth`, the tier or the effort was too
low; `contract`, the delegate broke the escalation contract; `env`, the
environment failed. The row goes through the write path, so `undo` and
`restore` take it back with the status.

The `CHECK` constraints the migrations add, each one a check rule the
schema makes impossible (section 5):

| Table | Constraint |
|---|---|
| goals | `quote <> ''`; `stamp` without a leading `(`; `title`, `short`, `context` NULL or `<> ''` |
| criteria | `mark IN (' ','x','-')`; not both `evidence` and `why` |
| facts | `pointer <> ''` |
| decisions | `by IN ('user','me')`; `date` matches `____-__-__` |
| pieces | `status IN (planned,out,back,verified,blocked,dropped,kept)` |
| pieces | kept: `kept_reason <> ''` and no route; else `model`+`effort` or `peer` |
| pieces | `model`, `effort` in their lists; `done_when` NULL or `<> ''` |
| pieces | `status <> 'verified'` or `evidence <> ''` and `verified_by` set |
| pieces | `risk_rating BETWEEN 0 AND 10`; `claimed_by` set exactly while out |
| piece_links | after: `after_id` set and `<> piece_id`; for: `criterion_id` set |
| piece_awaits | `word` in the list; `what <> ''` iff other |
| piece_criteria | `mark IN (' ','x','-')` |
| piece_returns | `from_status IN ('out','back')`; `cause IN ('brief','split','depth','contract','env')` |
| questions | `risk_rating BETWEEN 0 AND 10` |
| question_sees, question_pictures | exactly one target column set |
| pictures | `name <> ''`; `type` in the served list |
| links | `kind` and its ends: answers X→O; replaces X→X or O→O; rests_on X→F or C; led_to X→P or O; `to_row` set |
| counters | `kind IN ('P','O','D','C','F','N','X')` |

A `pictures.name` is unique per ledger with its `path`; a mockup placed
as a directory is one `name` with a row per file, `path` the file's
place under it, the page the viewer opens being the one `mockup`'s
picking rule names. A `question_pictures.name` is checked by the
writer against `pictures` of the same ledger (a foreign key cannot name
a non-unique column). `links.to_row` is a row id in the table
`to_kind` names (`X` decisions, `O` questions, `F` facts, `C`
constraints, `P` pieces); SQLite cannot key one column to five tables,
so the rule `links` (section 5) proves the target exists, and the
writer resolves it inside the transaction.

**A ledger's address** is the path its file had:
`PLACE/LEDGER.md` or `PLACE/LEDGER-NAME.md`, resolved against the
current directory and never touched on disk. Every command
takes it as its `PATH`. A live ledger is unique by
`(place, name)`; a closed one keeps its row with `closed_at` set, so a
new ledger can take the address. The viewer's URL id is
`sha1(address)[0, 10]`.

## 2. The write path

Every command that changes a ledger runs inside one call:

```ruby
Ledger::Write.run(journal, address, command, argv, own:, dry:) do |change|
    pid = change.next_id("P")          # U3, inside the transaction
    change.insert(:pieces, n: pid, ...) # every row change goes through
    change.update(:pieces, row, status: "out", claimed_by: session)
end
```

1. `BEGIN IMMEDIATE`: the write lock is taken before anything is read,
   so two writers never read the same state.
   A writer still waiting after 10 s is refused, exit 2, "journal is
   locked by another writer".
2. Read the ledger's *before* snapshot (`Ledger::Snapshot`, every row
   of the ledger, the shape every reader uses).
3. Insert the `events` row: time in ms, actor (`session:` +
   `CLAUDE_CODE_SESSION_ID` when set, else `cli`; `viewer:<user>` from
   the viewer), command, argv as JSON. **One event per
   command** (U1), whatever it touches: `answer --take` is one event
   whose rows include the inbox entries it took.
4. The block's changes go through `change`, which writes the row and
   an `event_rows` line with its JSON before and after.
5. `change.next_id(kind)` is `UPDATE counters SET last = last + 1 …
   RETURNING last` (U3): an id answered, dropped or undone is never
   given again, and two writers cannot take the same one.
6. Read the *after* snapshot and run the checks on both (section 5).
   The write is refused, and the transaction rolled back, when *after*
   fails a rule *before* passed or names `own` (the id written) in a
   failure: a write may not leave a ledger worse than it found it.
7. `--dry-run`: print the unified diff of `show` before and after
   (`--- ADDRESS`, `+++ ADDRESS (after)`), "dry run: nothing written",
   roll back. Exit 0, or 2 with the refusal it would give.
8. `COMMIT`; print what the command prints (section 4), the new id
   alone on the first line for `piece new`, `ask`, `fact`,
   `constraint`, `criterion new`, `renumber`, `decide`,
   `answer` and `word` (each files a decision, so each gives an
   `X<n>`), then the status line.

**The viewer as a writer.** The viewer's inbox entries and its takes go
through the same call, in-process, actor `viewer:<user>`, command
`inbox`; it is one more writer under the same lock, so a session and the
viewer at once, or two sessions, serialize on `BEGIN IMMEDIATE` and
neither reads a state the other is changing. *Decision*:
inside a request thread the viewer waits at most 2 s, not 10
(`busy_timeout` on its own connection), and answers 503, "the journal is
busy" and try again: a request thread held 10 s is the slow work
`sinatra-service` keeps out of requests.

**Links.** The commands that know an edge write it with the item:
`answer` writes `X<n>` answers `O<n>` and sets the question's
`closed_at`; `ask --replaces O<m>` writes `O<n>` replaces `O<m>` and the
decision it files; `piece … --by X<n>` writes `X<n>` led_to `P<n>`;
`decide --rests-on F2,C3 --led-to P4,O5` writes those edges. Every
target is resolved to its row inside the transaction and refused, exit
2, when it is not this ledger's.

**The claim (U12).** `piece P<n> --status out` stores the session id in
`claimed_by`; it needs one (`CLAUDE_CODE_SESSION_ID`, or `--session
ID`), and is refused without, exit 2. While a piece is `out` under one
session, `--status out` from another is refused, naming the holder and
the time of the event that claimed it. Any status other than `out`
clears the claim; a session taking over a piece another left sets it
`planned`, then `out`. Other changes from another session pass: a
resumed orchestrator records `back` and `verified`.

**What is not an event.** The beat (`ledgers.beat_line`, `beat_count`,
written by `check` without `--peek`) and the counters: neither is the
ledger's content, an undo must not move them, and a beat row would read
as activity to U14. *Decision.*

**Undo (U1).** The ledger's last event whose command changed its items
(not `take`, `inbox`, `close`, nor `undo` itself) is reverted: every
`event_rows` line's *before* is written back, provided the row still
equals its *after*; inbox entries are never reverted (the user's
channel, and the takes, are never undone). The revert is itself an
event (`undo`, `undoes` = that event). One level: when the last such
event is an undo, "nothing to undo". A `pictures` row is never written
to `event_rows` (its bytes would double the journal) and never
reverted: undoing a `mockup` event puts back the question's
`question_pictures` rows alone, the blobs stay, as the files on disk
stayed (S1).

**Restore (U1).** `restore ADDRESS --to E<n>` reverts, in one
`restore` event, every item-changing event of the ledger after `E<n>`,
newest first, by the same rule. Without `--to` it lists the ledger's
last ten events (`E<n>  time  actor  command  summary`) and exits 2.

## 3. Derived states (U2, U14)

Stored: `planned`, `out`, `back`, `verified`, `blocked`, `dropped`,
`kept` (with its reason). Everything below is computed per read from
the snapshot and the events, never stored.

| State | Rule |
|---|---|
| settled | `verified` or `kept` |
| unfinished | `planned`, `out` or `back` (`--final` fails on these) |
| in flight | `blocked`, `back`, `out`, `planned`, in that urgency |
| ready | `planned` and every `after` piece settled |
| awaiting | its `piece_awaits` rows, in position order |
| stalled (U14) | `out`, and no event row touching it for more than the stall budget: 60 minutes, `LEDGER_STALL_MINUTES` overrides (S2) |
| question preparing | its `by` piece or a `pending` picture's piece is not settled |
| question answerable | not preparing |
| asked since (O<n>) | the later of the question's insert event and the event that last settled its preparer |
| asked since (P<n>:word) | the event that inserted that `piece_awaits` row |
| stuck (`unchanged ×N`) | the status line equals `beat_line`; `beat_count` is N |

"Touching it" means an `event_rows` line on the piece's row or on one of
its `piece_links`, `piece_awaits`, `piece_scopes`, `piece_briefs`,
`piece_criteria` rows.

**The stall budget (S2).** `Ledger::Derive::STALL_MINUTES = 60`, read
once at start from `LEDGER_STALL_MINUTES` when set; a value that is not
a whole number above 0 is refused, exit 2, at the first command that
derives (hard error over a silent default). A question with
`closed_at` set is in no derived state.

**The status line**, with `stalled:` (U14) after `blocked:`:

```
Status — criteria 3/4 · pieces 14/15 verified, 1 kept · out: P2 ·
back: … · blocked: … · stalled: P2 · waiting on you: O3 · being
prepared: O9 (P36) · your word: P47 (commit, deploy) · from the
viewer: N1 · done: propose close
```

on one line; `· unchanged ×N` appended by `check` (not `--peek`) when it
repeats.

## 4. The command contract

`bin/ledger` is a POSIX sh launcher (section 7) that runs
`Ledger::CLI.run(ARGV)` (`lib/ledger/cli.rb`, OptionParser, one class
per command in `lib/ledger/commands/`). Exit status: 0 done, 1 a check
that fails (or a wait that timed out), 2 a refusal or a usage error,
nothing written. Every writer takes `--dry-run` but `new`, `take`,
`close` and `mockup`. "Checks" means the write path's step 6. A refusal
that comes from the schema (a CHECK, a unique key) is reported as the
command's refusal, exit 2, nothing written.

| Command | Output | Refusals (exit 2) |
|---|---|---|
| `new PATH --goal --title --short [--context] [--date] [--carry CLOSED]` | the address | address live; title fails the title rule; empty `--short`; `--carry` names no closed ledger (it takes an address, its newest close, or `L<id>`) |
| `goal PATH --quote --title --short [--context] [--date] [--dry-run]` | the new Goal block, status line | title; empty short; quote under 4 words (a go-ahead); checks |
| `check [--final] [--peek] [--fix-hints] [--json] PATH` | `ok  name` / `FAIL name -- detail` per rule, `  hint:` after a FAIL, status line (the beat, unless `--peek`); `--json` prints JSON v1 | exit 1 on any FAIL |
| `show PATH [ID] [--json]` | no ID: the whole ledger as Markdown; an ID (`P`, `O`, `D`, `C`, `F`, `X`, `Z`): its fields as `key: value` lines, links as `answers: O3`, `rests-on: F2, C3` lines; or JSON v1 | unknown id |
| `status PATH [--json]` | the status line; JSON v1 | |
| `survey [DIR] [--peer NAME] [--json]` | read-only, for a session with no goal: each live ledger at DIR (the current directory by default) or under it: its address, its status line as `check --peek` prints it, its pending entries as `inbox` prints them; with `--peer`, the pieces of any live ledger whose `peer` is exactly NAME, one `ADDRESS  piece line` each; nothing found says so; no beat, no event; JSON v1 | |
| `stats [PATH] [--json]` | one row per route over every ledger, live and closed, or one (a live address, or `L<id>` live or closed): `route` (`MODEL, effort: E`, `peer: NAME` or `kept`, the route a piece has now), `pieces`, `first-pass` (of the pieces verified, those never back to planned from out or back), `blocked` (ever blocked, of all), `out, median` (each span from the event setting a piece out to the next that changes its status; a piece still out counts none), `returns` (by cause from `piece_returns`, a return in `event_rows` with no row as `unrecorded`); JSON v1. Only the events still in force count: no undo or restore, nor an event one of them reverted (unless a later restore reverted that revert). Reads `events`, `event_rows` and `piece_returns`, writes nothing (no event, no beat) | unknown address or `L<id>` |
| `close PATH [--take N<n>…]` | `closed: ADDRESS (L<id>)`, then `noticed, to carry: N` and the lines; `--take` takes the entries (the viewer's Close, `ref` `close`) in the close's event | `--final` fails (FAIL lines, exit 1), a refused close taking nothing; inbox pending besides the entries taken; an entry unknown or taken |
| `inbox PATH [--wait [--timeout S] \| --follow [--quiet S]]` | the pending entries, or "inbox: nothing pending"; polls the ledger's newest event id each second | `--wait` timeout exit 1 |
| `take PATH N<n>…` | `taken: …; pending: …`; one `take` event setting `taken_id` | unknown id; "already taken at TIME: another session filed it" |
| `piece PATH new\|P<n> [--status --route --title --what --done-when --evidence --after --for --problem --risk --plan --scope --awaits --verified-by --session --by X<n> --cause C --dry-run]` | the new id (new), the piece line, status line | target shape; no such piece; title, detail; scope grammar or a word not awaited; new without title; awaiting without problem and rated risk; no route and not kept; a return (`--status planned` from out or back) without `--cause` or with a cause not in `brief`, `split`, `depth`, `contract`, `env`; `--cause` on any other change; out without a session, or out under another holder; verified without `--verified-by`; checks |
| `ask PATH QUESTION --title [--choices --by --items --see --problem --risk --recommend] (--mockup N \| --pending P \| --no-picture WHY) [--replaces O<n>] [--dry-run]` | the id, the line, a warning at 7–8 options, the picker card (dry run), status line | title, detail; problem and rated risk; empty question; not exactly one picture decision; pending piece missing or dropped; no picture of that name in the journal; `--by` dropped; option grammar; `--items` without `--choices`; `--replaces` not open or with an untaken entry; checks |
| `answer PATH O<n> --decision [--date] [--take N…] [--replaces X<n>] [--dry-run]` | the id (`X<n>`), the decision line, the take line, status line | not open; empty decision; unknown or already taken entry; checks |
| `word PATH P<n> --word W [--date] [--take N…] [--dry-run]` | the id (`X<n>`), the decision line, the piece line, the take line, status line | not P<n>; no piece; empty; awaits no word; a word not awaited; unknown or taken entry; checks |
| `mockup PATH FILE\|DIR… --question O<n> [--name] [--replace]` | `placed …` per file, the question line, `viewer: /l/ID (…/m/ID/NAME)` | no question; symlink; missing; nothing; a name `mockup:` cannot spell; a type not served; not open; a name already placed; `--name` not placed; no single page, image or text to pick |
| `choice PATH O<n> (--add \| --drop) [--dry-run]` | the question line, the card (dry run), status line | not O<n>; not open; no choices; `--add` without ` = `; `--drop` unknown; option grammar; checks |
| `fact PATH TEXT [--dry-run]` | the id, the line, status line | no ` — pointer` (text and pointer split at the first ` — `); checks |
| `constraint PATH QUOTE --where W [--dry-run]` | the id, the line, status line | empty quote; empty where |
| `decide PATH TEXT --by user\|me [--note] [--date] [--rests-on F<n>,C<n>…] [--led-to P<n>,O<n>…] [--replaces X<n>] [--dry-run]` | the id (`X<n>`), the line, status line | by; empty; a target not this ledger's or of another kind; checks |
| `noticed PATH TEXT [--dry-run]` | the line, status line | empty |
| `criterion PATH new --text T`, `criterion PATH D<n> (--met E \| --unmet W \| --text T) [--dry-run]` | the id (new), the line, status line | not D<n>; empty value; no such criterion; `--text` with `--met` or `--unmet`; checks (`criteria-pieces`) |
| `edit PATH ID --text T [--dry-run]` | the line, status line | unknown or other kind of id; a `P<n>` (its detail is `piece --what`'s); empty text; checks |
| `renumber PATH OLD NEW [--dry-run]` | NEW, `renumbered OLD -> NEW: its heading and N reference(s)`, status line | shapes; kinds differ; same; OLD heads nothing; untaken entry about OLD; NEW given before (counter) or referenced; checks |
| `undo PATH [--dry-run]` | `undone: ADDRESS is back as it was before E<n>`, status line | nothing to undo; a row changed since |
| `restore PATH [--to E<n>] [--dry-run]` | `restored: ADDRESS is back as at E<n>`, status line; without `--to` the ledger's last ten events (`E<n>  time  actor  command  summary`) | no `--to` (it lists them); E<n> not this ledger's; nothing after it; a row changed since |

`help [WORD]`, `--help` and `-h` in place of WORD, or no word at all,
print the words by section with each one's SUMMARY (`lib/ledger/help.rb`);
`help WORD` and `-h` or `--help` among a word's arguments print its
synopsis, summary and described options. Help is an answer: standard
output, exit 0, nothing read. An unknown word stays a usage error.

Beside the ledger's own words, the launcher takes `bin/ledger hook
NAME` (section 7).

**Every prose item has a writer.** A journal has no hand edit, so each
item is written by a command: `criterion new --text` and `criterion D<n>
--text` for Done when, `edit ID --text` for an `F`, `C`, `X` or `O` item
(a fact's text, a constraint's line, a decision's body, a question's
detail), a noticed line and the latest Goal's title. The Goal quote stays
append-only through `goal`. `new` writes the placeholder criterion
`D1: <a check something other than opinion can pass>`, which `criterion
D1 --text` then replaces. Two targets have no id printed in the
Markdown: `edit PATH goal --text` sets the latest Goal block's title
alone, and an `Out of scope, noticed` line has a `Z<n>` row id, shown by
`show --json` and `show PATH Z<n>`, which `edit Z<n> --text` takes. A
piece's detail has one writer, `piece P<n> --what`: `edit` refuses a P
id, one writer per column.

## 5. The check rules

`check` runs the rules below on a `Ledger::Snapshot`, in this order
(`lib/ledger/checks/runner.rb`, each rule in its module under
`lib/ledger/checks/`); `--final` adds the last three, and `close` adds
its own (no entry of the viewer pending). `--fix-hints` prints one hint
per rule, its commands spelled for `bin/ledger`
(`lib/ledger/checks/hints.rb`).

| Rule | Checks | Home |
|---|---|---|
| goal-titled | each Goal block's Title passes the title rule | `checks/goal.rb` |
| goal-revision | a revised Goal quotes at least 4 words | `checks/goal.rb` |
| criteria | at least one criterion | `checks/criteria.rb` |
| open-choices | no option with a colon, no drop or ignore option, items only with choices | `checks/open.rb` |
| open-described | problem and risk; once answerable, `X = …` for each option and a recommend | `checks/open.rb` |
| open-picker | the picker grammar, on every open question, and no two open questions offering the same options | `checks/open.rb`, grammar in `text/picker.rb` |
| self-routed | no piece in flight, awaiting no word, routed `peer:` to the ledger's own project | `checks/pieces.rb` |
| links | every link names a row of this ledger, and `after` never loops | `checks/links.rb` |
| pieces-awaits | `start` only on a planned or kept piece, a finishing word on a settled one, a scope only for a word awaited | `checks/pieces.rb` |
| titles | pieces in flight and open questions: the title rule | `checks/pieces.rb`, `checks/open.rb` |
| details | a detail not mostly ids | same |
| pieces-order | out, back or verified only once `after` is settled; none waits for a dropped piece | `checks/pieces.rb` |
| criteria-pieces | no criterion met while a piece serving it is unfinished | `checks/criteria.rb` |
| case-rated | a rated risk on every open question and on every piece awaiting a word, a problem on that piece, Title and In short on the latest Goal | `checks/open.rb`, `checks/pieces.rb`, `checks/goal.rb` |
| verified-by | a verified piece is not verified by its own route | `checks/pieces.rb` |
| final-pieces | `--final`: none planned, out or back | `checks/final.rb` |
| final-awaits | `--final`: no word owed | `checks/final.rb` |
| final-criteria | `--final`: every criterion `[x]` with evidence or `[-]` with why | `checks/final.rb` |

What no rule has to say, because the schema makes it impossible
(section 1): ids unique per ledger, a status, a mark, a model, an effort
or an await word outside its list, a piece without a route (or a kept
one with one), a verified piece without evidence or without
`verified_by`, an out piece without its claim, a risk outside 0 to 10, an
empty pointer, Goal quote or Goal field, or done-when, a link, a `see` or a
picture with the wrong number of targets, a link whose ends are not the
kinds its edge allows. A line that does not parse cannot exist: no line
is stored.

## 6. JSON v1 for readers (U4)

Every JSON output is one object whose first key is `"schema": 1` and
second `"kind"`. A reader refuses a schema number it does not know (hard
error). The viewer reads this through `Ledger::Read` in-process, and any
other reader through `--json`; the hooks read the `Snapshot` and the
`Derive` of a ledger directly and need no JSON.

- `check --json`: `{schema, kind: "check", reports: [{name, ok, detail}],
  status}`.
- `status --json`: `{schema, kind: "status", line, criteria: [met,
  total], pieces: {verified, live, kept}, out, back, blocked, stalled,
  waiting, preparing: [[O, P]], words: [{piece, words}], from_viewer,
  propose_close}`.
- `survey --json`: `{schema, kind: "survey", dir, ledgers: [{address, status,
  inbox: [{id, text}]}], peer: null \| {name, pieces: [{ledger, id, line}]}}`.
- `stats --json`: `{schema, kind: "stats", groups: [{route, pieces,
  first_pass_verified, blocked_share, median_out_minutes, returns:
  {cause: count}}]}`, shares as fractions 0..1, `null` where there is
  nothing to divide or no span out.
- `show PATH ID --json`: `{schema, kind: "item", item}`, the item's
  object below; `show PATH ID` prints its scalar fields as `key: value`,
  lists joined by ` | `, and a piece's returns one a line, `return:
  CAUSE, from STATUS, TIME`.
- `show PATH --json`: `{schema, kind: "ledger", …}`:

| Key | Content |
|---|---|
| ledger | `{id, address, place, name, project, url_id, updated_at, closed_at}` (`updated_at` is the last event's time) |
| goals | `[{stamp, date, revised, title, short, context, quote}]` |
| criteria | `[{id, mark, text, evidence, why, line}]` |
| constraints | `[{id, text, quote, line}]` |
| facts | `[{id, text, pointer, line}]` |
| decisions | `[{id, date, body, by, note, subject, line}]` (`id` is `X<n>`) |
| links | `[{kind, from, to}]`, visible ids at both ends |
| closed_questions | the `questions` shape plus `closed_at`, the rows with `closed_at` set, oldest first (the graph page reads them) |
| pictures | `[{name, files: [{path, type, size}]}]` |
| pieces | `[{id, status, kept_reason, route: {model, effort, skills, peer} \| null, route_text, title, detail, done_when, evidence, after: [P], for: [D], awaits: [{word, what}], scope: [{word, text}], problem, risk: {rating, text}, plan, verified_by, claim: {session, since} \| null, ready, stalled, settled, brief: {version, at} \| null, criteria: [{text, mark, evidence}], returns: [{cause, from, at, actor}], line}]` (`returns` oldest first) |
| questions | `[{id, title, detail, problem, risk: {rating, text}, recommend, choices: [{label, effect, cost, text}], items, by, see: [ids], pictures: [{name} \| {pending}], preparing: P \| null, preparing_status, asked_since, line}]` |
| refs | `{id: {kind, line}}` for C, D, F, P and X |
| noticed | `[line]` |
| inbox | `[{id, at, ref, payload, malformed, taken, taken_at, taken_by}]` |
| asked | `{"O3": since, "P4:commit": since}` (derived, section 3) |
| status | the status line |
| fails | `[{name, detail}]` |

`line` is the item's line exactly as `show` prints it, so a reader never
rebuilds one. Times are ISO 8601 in local time with the offset.

**The index document.** `{schema, kind: "index", ledgers}`, one entry
per ledger, live first, then by `updated_at`, newest first: `id`,
`address`, `project`,   `title`, `short` (of the latest Goal),
`created_at`, `updated_at`,   `closed_at`, `status` (the status line),
`waiting` (the open questions   answerable now), `words` (the pieces
awaiting a word) and `pending`   (the inbox entries not taken).

## 7. Hooks, the launcher and the resume view

**The launcher.** `bin/ledger` (POSIX sh, `#!/bin/sh`) resolves its own
checkout, picks the interpreter — `$LEDGER_RUBY` when set (refused,
exit 1, when it is not executable), else `/usr/local/bin/ruby` when
executable (the native port, where the Linux-compat side's own `ruby`
is another build), else `ruby` on `PATH` — and execs it with
`BUNDLE_GEMFILE`, `BUNDLE_LOCKFILE` and `BUNDLE_FROZEN=true` exported
for the checkout, `-rbundler/setup`, `-I lib`. The lockfile is named
because one inherited from another project's bundle beats the one
Bundler derives from `BUNDLE_GEMFILE`, and that project's lockfile
would be rewritten with this checkout's gems; frozen, a lockfile that
does not match stops the command instead of being rewritten. The three
are exported before every path, the no-bundler hooks included, since a
leaked `RUBYOPT` can load bundler there too. For the two words that read no journal, `hook heartbeat` and
`hook journal-write`, it passes `-I lib` alone: measured 2026-11-20 on
`/usr/local/bin/ruby`, a bare start is 0.03–0.06 s, `-rbundler/setup`
0.11–0.19 s, Sequel loaded and a database opened 0.20 s, and the
heartbeat runs after every Bash call. Sessions run it from the Bash
tool; the hooks run it from the Linux side, where `/usr/local/bin/ruby`
is the native port reached by absolute path. A launcher failure exits
1, never 2: a hook's 2 would block the session.

`ruby` on `PATH` from the Linux side is Linux ruby 3.3.8 without the
bundle's native sqlite3: that fallback fails there, and the code's
Ruby 3.4 idioms (`it`) fail on it anyway. Recorded, not designed
around: the user's decision.

**Registration.** The orchestration skill registers the hooks: five in
its SKILL.md front matter, `session-start` in its `hooks.json`
(SessionStart, no matcher). Each command finds the tool by PATH and is
a no-op without it: `command -v ledger >/dev/null 2>&1 || exit 0; exec
ledger hook NAME`. On this host `ledger` is the relative symlink
`~/bin/ledger -> ../Repos/ledger/bin/ledger`; the launcher follows the
chain with `readlink` to find its checkout.

Each hook reads the payload on stdin, writes nothing to the journal, and
turns any error of its own into exit 0. The session's ledgers
are the live ledgers whose `place` is the
payload's `cwd`, `cwd/.claude`, or its `scratchpad_dir`.
`CLAUDE_CODE_SESSION_ID` is set in the Bash tool's environment, so the
claim (U12) needs no `--session` in the common case. Stop starts Ruby
twice (two hook entries); section 8 records merging them as an
objection.

| Hook (event, matcher) | Reads | Does |
|---|---|---|
| `heartbeat` (PostToolUse, Bash) | the tool output | a command naming `ledger … check\|status`: the last `Status —` line as `systemMessage`. Stdlib only, no bundler, no Sequel: a bare interpreter start after every Bash call (the launcher's rule above) |
| `brief-constraints` (PreToolUse, Agent) | `constraints.quote` of the session's ledgers | deny a brief naming a path a constraint's quote names without carrying the quote (whitespace and case folded) |
| `journal-write` (PreToolUse, Bash) | the command words | deny a command that writes the journal by hand: `sqlite3` on it without `-readonly`, a redirect, `cp`, `mv`, `rm`, `install`, `tee` onto it or its `-wal`/`-shm`, `sed`, `perl` or `ruby` in place, interpreter code opening it; a segment whose program is the launcher passes; the refusal names the `bin/ledger` commands. Stdlib only |
| `finish` (Stop) | snapshot, checks | a ledger with a piece, none planned, out, back or blocked, none awaiting a word and no question open, that fails `--final`: refuse once with the FAIL lines and the finish steps; on the retry the stop goes through |
| `inbox` (Stop) | inbox entries | pending entries refuse the stop once, verbatim, with the filing steps; on the retry the stop goes through |
| `session-start` (SessionStart) | snapshot, entries | pending entries with the steps (every source); for `source` in startup, resume, compact also the resume view (U5) |

**The resume view (U5).** One `additionalContext` text, at most 10 000
characters across the session's ledgers, the budget shared equally
among them; the inbox part is outside the budget (the user's words are
never cut). Per ledger, every line as `show` prints it:

1. `Ledger ADDRESS — bin/ledger show ADDRESS for the whole`
2. the status line;
3. every Goal block, verbatim;
4. Constraints, verbatim;
5. Open: each question's line;
6. In flight: each blocked, back, out, planned piece's line, `(ready)`
   or `(stalled)` appended where derived.

Over budget, the view drops from the end: pieces in flight, then
questions, each replaced by `… N more: bin/ledger show ADDRESS`. When
the goal blocks and constraints alone exceed it, the latest Goal block
stays whole and the constraints become their ids with the same
pointer: the quote is never cut mid-word. *Decision*: the order and the
fallback.

**The skill's SKILL.md (U7)** says, under The ledger, that the ledger is
the task list: a session does not keep a second one in TaskCreate or
TodoWrite.

## 8. Where things live

The gate is `bundle exec rake` at the repository's root (the minitest
suite, then the house rubocop rules), with `LEDGER_JOURNAL` at a file in
a temporary directory per test.

| Area | Files |
|---|---|
| journal, write path | `lib/ledger.rb` (the `Ledger::Error` family), `lib/ledger/journal.rb`, `migrations/001_journal.rb`, `migrations/002_piece_returns.rb`, `snapshot.rb`, `write.rb` |
| text rules | `lib/ledger/text/{title,picker,awaits,risk,options}.rb`, pure functions |
| render | `lib/ledger/render/markdown.rb` (`show`), `render/json.rb` and `read.rb` (JSON v1) |
| derived states, checks | `lib/ledger/derive.rb`, `lib/ledger/checks/*.rb` |
| commands | `lib/ledger/cli.rb`, `lib/ledger/commands/*.rb`, `bin/ledger` |
| history, inbox, pictures | `lib/ledger/history.rb`, `inbox.rb`, `pictures.rb` |
| hooks | `lib/ledger/hooks/*.rb`, registered by the orchestration skill (SKILL.md's front matter, `hooks.json`) |
| viewer | `lib/ledger_viewer/`, `views/`, `public/`, `config.ru`, `bin/ledger-viewer`; it reads `Ledger::Read` and writes through `Ledger::Inbox.append` |

The viewer lists every live ledger of the journal. Its pictures are
served from `pictures` at `/m/ID/NAME[/path]`, its sign-in state (users,
invitations, passkeys, keys) is sesam's `SequelStore` in the same file
(`Sesam.migrate` runs first), and `rake user:carry` moves a JSON store's
users in once. A page draws a piece or a decision back to the user's
words from the `links` of JSON v1 (`lib/ledger_viewer/links_graph.rb`,
`views/ledger/links.erb`).

Settled objections, kept as decided:

- `edit P<n> --text` and `piece P<n> --what` would write one column two
  ways: `edit` refuses a P id.
- `piece --by X<n>` and `ask --by P<n>` give one flag word two meanings
  (the decision behind a piece; the piece preparing a question).
- Stop runs two hooks, so two Ruby starts; one `hook stop` word running
  inbox then finish would cost one, at the price of six hook names.

Decisions of the build, reviewable: the `LEDGER_JOURNAL` name; the
address is the path spelling of a ledger file; `beat` and counters outside the
events; `case-rated`; `journal-write`; the resume view's order and
fallback; `--no-picture` stored; event times in milliseconds, as sesam
keeps its own; questions kept after an answer; `pictures` outside
`event_rows`; the viewer's 2 s wait and 503; `decide`, `answer` and
`word` print their `X<n>` first; the launcher's bare start for the two
journal-free hooks; the tool found by PATH, its hooks a no-op without
it.

Behaviours that follow from the design:

- `undo` reverts an event; `restore` takes `--to E<n>`.
- An undone `piece new` does not give its id back.
- `verified_by` and the claim are in the JSON and the events, not in the
  Markdown.
- The status line names stalled pieces, `stalled:`.

## 9. Borrowed from

The upgrade codes above come from a survey of agent trackers made on
2026-11-20. What was built from it, by source:

- **Claude Code hooks** (https://code.claude.com/docs/en/hooks): the
  SessionStart payload's `source` and its `additionalContext` of at
  most 10 000 characters carry the resume view (U5,
  `lib/ledger/hooks/session_start.rb`,
  `lib/ledger/hooks/resume_view.rb`); its Task
  tools are why the skill names the ledger as the task list (U7).
- **Beads** (https://github.com/gastownhall/beads,
  https://pkg.go.dev/github.com/steveyegge/beads): `bd ready` as the
  derived *ready* state (U2, `Ledger::Derive#ready?`); `bd update
  --claim` as the claim of a piece sent out (U12, `pieces.claimed_by`);
  `bd prime`, re-injecting the workflow after compaction, as the resume
  view (U5).
- **Task Master** (https://github.com/eyaltoledano/claude-task-master,
  https://docs.task-master.dev/capabilities/task-structure): the next
  task is one whose dependencies are satisfied, as a planned piece is
  ready once its `after` pieces are settled (U2).
- **Spec Kit** (https://github.com/github/spec-kit), **HumanLayer**
  (https://github.com/humanlayer/humanlayer) and Claude Code's
  cross-session messaging
  (https://code.claude.com/docs/en/cross-session-messaging): surveyed;
  nothing of theirs is built.

The rest is attributed by the survey's own comparisons, not by a
lineage the trackers' authors claim:

- U1, the event log (section 2), and U11, `verified_by`: closest to
  taskops (events.jsonl as truth, a verifier's pass).
- U14, stalled (section 3): closest to Gas Town's Witness for stuck
  agents.
- U16, `piece_criteria` (schema only): closest to Backlog.md's
  acceptance criteria.
- U3, sequential ids; U4, JSON v1 (section 6); U10, `piece_briefs`
  (schema only): own design, no source.
