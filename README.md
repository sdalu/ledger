# ledger

The orchestration skill's ledger as a command: one SQLite journal that
holds every ledger of the machine and its history, the hooks that keep a
session to it, and a local viewer where the user answers.

## At a glance

A session writes its ledger only through `bin/ledger`; the hooks read
the journal and never write a ledger (two record sessions for the
waker); the viewer writes the user's entries and the waker's switch.
`bin/ledger-waker` rings an idle session when an entry of the user's
waits. `docs/journal.md` is the design note: the schema, the write
path, the derived states, the command contract, the check rules, the
hooks, the waker.

```text
 ┌───────────────────┐  ledger WORD PATH  ┌────────────────────────────┐
 │ session           ├───────────────────▸│ journal (SQLite, Sequel)   │
 └─────────┬─────────┘                    │ ledgers, items, events,    │
           │ Bash, Agent, Stop,           │ inbox entries, pictures,   │
           │ SessionStart                 │ sesam's sign-in tables     │
           ▼                              └──────┬───────────────┬─────┘
 ┌───────────────────┐  reads; writes sessions   │               │
 │ ledger hook NAME  │◂──────────────────────────┘               │
 └───────────────────┘                                           │
 ┌───────────────────┐  reads; writes entries, the switch        │
 │ bin/ledger-viewer │◂──────────────────────────────────────────┘
 └───────────────────┘
```

## Reaching it

Sessions and hooks call it as `ledger` on PATH; on this host that is a
relative symlink, `~/bin/ledger -> ../Repos/ledger/bin/ledger`, which
the launcher follows to find its checkout. The orchestration skill's
hooks run `command -v ledger >/dev/null 2>&1 || exit 0; exec ledger
hook NAME`, so a session without the tool runs no hook.

`bin/ledger` is a POSIX sh launcher: it runs the interpreter
`$LEDGER_RUBY` names, else `/usr/local/bin/ruby` when executable, else
`ruby` on the path, under the checkout's bundle. The hooks run from the
Linux-compat side, where a bare `ruby` is another build without the
bundle's SQLite gem, so the absolute path is how they reach the native
one; `$LEDGER_RUBY` overrides it. The heartbeat and `journal-write`
hooks read no journal and start without the bundle (a bare start is
0.03 to 0.06 s against 0.2 s with Sequel loaded, measured 2026-11-20),
since they run around every Bash call. A launcher failure exits 1,
never 2, which would block the session.

`rake check` checks the gems, the configuration, the external tools and
the addresses; `rake help` lists every task.

## The commands

`bin/ledger WORD …` is the one entry point (`lib/ledger/cli.rb`,
one class per word in `lib/ledger/commands/`); `docs/journal.md`
holds the contract word by word: flags, output, refusals. `ledger help`
(also `ledger`, `--help`, `-h`) lists the words by section with their
summaries, and `ledger help WORD` (or `ledger WORD --help`) a word's
options, each described; help exits 0. Exit status: 0
done, 1 a check that fails or a wait that timed out, 2 a refusal or a
usage error, with nothing written. PATH is a ledger's address, the path
its file would have (`.claude/LEDGER.md`, `LEDGER-name.md`), resolved
against the current directory and never touched on disk.

`new` writes the ledger with the goal quoted under its `Title:`,
`In short:` and optional `Context:` lines (the session's words: a quote
alone reads as nothing to someone coming to it cold) and a placeholder
criterion D1, which `criterion PATH D1 --text` replaces; it refuses an
address a live ledger holds. `goal` appends a revised Goal block the
same way and refuses a quote of fewer than 4 words, a go-ahead that
belongs under Decisions (`goal-revision`; `goal-titled` checks the
title). Each Goal block has an id, `G1` for the first, the next number
for each revision, printed in its label (`Goal G2 (2026-11-21, revised,
verbatim):`). A block stays active until `goal PATH G<n> --done
EVIDENCE` marks it done (a `Done: EVIDENCE` line under its In short);
`goal PATH G<n> --undone` makes it active again. Both refuse an unknown
`G<n>`, and `--done` refuses empty evidence, a block already done, and
`--quote`; `--undone` refuses a block not done. `check` verifies what the schema cannot (the rules are listed in
`docs/journal.md`, section 5): titles and details, codes from
elsewhere (a W1 not named in words or pointed to), links, awaited words,
the picker grammar, rated cases, a verified piece's `--verified-by`, the
`--final` rules. The schema refuses the rest before a check could see
it: a piece that is neither kept (with its reason) nor routed with model
and effort (and, where its brief names skills, those too, `sonnet,
effort: medium, skills: c`, so a resumed session briefs it the same
way) or else `peer: SESSION` for a piece another Claude session does; a
verified piece without evidence; an empty `done when:`.
`status` prints the heartbeat line, naming the
open questions (`waiting on you: O1, O2`) and each deferred piece
with what it waits on (`deferred: P6 (three closures)`); `check
--final` refuses a finish with pieces still out or deferred, or a
criterion unmarked; `close` leaves
the ledger's row in the journal marked closed, out of every hook's and
the viewer's sight, and refuses while a viewer entry is pending; a
close done first prints an after-action block, `after action:` with
the returns and their causes, the pieces blocked or stalled out over an
hour, the time each question took to answer and the decisions by me,
read from the ledger's events with the numbers `stats` counts.
`close PATH --abandon` closes a ledger unfinished, `--final` not
required: in the same event every piece planned, out, back or blocked
is dropped, awaiting no word after, and every open question closed by
a decision by user `abandoned with the ledger`, the history kept; a pending entry still
refuses it, and it ends `abandoned: ADDRESS (L<id>)`. Nothing undoes a
close. It checks shape, not truth: a paraphrased goal in quote marks
passes.

`survey [DIR] [--peer NAME]` is the read for a session with no goal: the
live ledgers at DIR (the current directory) or under it with their status
lines and pending entries, and with `--peer` the pieces routed `peer: NAME`
in any live ledger; it writes nothing and counts no heartbeat.

`show PATH` prints the whole ledger as Markdown (PATH an address or
`L<id>`, which reaches a closed one, its last line `closed: TIME` or
`abandoned: TIME`); `show PATH ID` prints
one item's fields (a piece, question, criterion, fact, constraint,
decision `X<n>` with its links, or a noticed line `Z<n>`), one `key:
value` per line, an unknown id exiting 2. `brief PATH P<n>` prints, as one JSON object and
writing nothing, what a brief for the piece is built from: the piece
(id, title, what, done when, route), the Goal blocks not done, every
constraint with its quote and where, the facts whose pointer names a
path the piece names or that are linked to it, the question it builds
with its answer, and the decisions by user that led to it; an unknown
piece exits 2. `stats [PATH]` prints a track
record per route (model and effort, each peer, kept) over every ledger,
live and closed, or one (`L<id>` reaches a closed one): pieces, the
share verified without a return, the share ever blocked, the pieces
ready and unsent now, the median
time out, the returns by cause; then, once a dispatch was announced, a
section `by assessment`, one table by highest axis and one by model:
the dispatches, the pieces first dispatched there, those of them
verified with no return, and each return by cause, laid on the piece's
last dispatch before it; and over every ledger a last line
`closed ledgers: N finished, M abandoned`; it writes nothing. `--json` on `check`,
`status`, `show` and `stats` prints JSON v1: one object whose first key
is `"schema": 1`, which the viewer and any other reader take and refuse
in any other number. `check --fix-hints` prints, after each FAIL line, one indented
`  hint: …` line naming the form expected and the command that fixes it.

Links between items sit on the line they belong to: `— after: P3, P5`
on a piece (it waits for those), `— for: D2` (the criteria it serves),
`— by: P28` on a question (the piece that answers or draws it). They
are rows, not text, so a link to nothing cannot be written. `check`
fails a loop through `after`, a piece `out`, `back` or `verified` before
what it waits for is verified or kept, or one waiting for a dropped
piece (`pieces-order`), and a criterion marked met while a piece serving
it is planned, out, back, deferred or blocked (`criteria-pieces`).
Decisions have ids `X<n>` and edges of their own: `answer` writes `X
answers O<n>`, `ask --replaces` and `decide --replaces` the replaced item,
`decide --rests-on F2,C3 --led-to P4,O5` the facts and constraints it
rests on and what it led to, `piece --by X<n>` the decision that led to
a piece. A question once answered keeps its row, so the edge has a
target. The viewer draws the graph of a piece or a decision back to the
user's words.

Every item has a writer, and no ledger is edited by hand. `piece
PATH new|P<n>` adds a piece with the next free id or changes one
(`--title`, `--what` for the detail, `--status`, `--route`,
`--done-when`, `--evidence`, `--after`, `--for`, `--by`, `--verified-by`,
`--cause`, `--no-picture WHY`, `--picture-pending WHY`, `--picture-holds WHY`, `--no-commit WHY`, `--hold WHY`, `--announce FILE`, `--status back --handback`, `--builds O<n>`,
`--status obsolete --obsoleted-by P<n>`, `--commits SHA[,SHA...]` (appends the commits that landed it), `--[no-]irreversible` (its step cannot be taken back: 3 more on the step risk of each word it awaits, `— irreversible` on its line), `--gate "NAME: STATE (DETAIL)"` (a gate's state, queued, running, passed or failed, one per name, a later state replacing it: `— gates: unit failed (2 failures)`), `--report FILE` (a helper's report, its status line and up to 12 lines, alone or with `--status back --handback`, which then stores it even on a piece not out, the status untouched: `— report: DONE_WITH_CONCERNS`); an empty value clears a link); a piece not done that
waits on an event to come, not on the user, is `--status deferred
--until CONDITION`, the event kept on its line (`— until: three
closures`) and in the viewer's remains until another status clears
it; `ask PATH --title TITLE "question"
[--choices "A = … | B = …"] [--recommend "A, why"] [--items "x | y"]
[--by P<n>] [--see F2] (--mockup NAME | --pending P<n> | --no-picture
WHY) [--replaces O<n>]` puts a question under Open (it refuses one
without a picture decision or breaking the picker grammar,
`check`'s `open-picker`; `--replaces` closes O<n> in the same write, a
Decision `by me`; `--dry-run` also prints the card's picker; `ask PATH
O<n> --by P<n>|none` sets, changes or clears the `--by` link of an open
question, and `check`'s `question-loop` fails a question asked by a piece
that awaits the user's word, which the write refuses to create); `answer
PATH O<n> --decision TEXT [--take N<n>…]` files the answer as a Decision
`by user`, prefixed `O<n>:`, closes the question and takes the viewer
entries, in one write; `word PATH P<n> --word W [--take N<n>…]` files
the user's word on a piece as a Decision `by user` and changes the piece
in the same write (`drop` sets it dropped; another word must be one the
piece awaits and leaves its `awaits` once every awaited word is given);
`fact PATH "TEXT — where found"`, `constraint PATH QUOTE --where W`,
`decide PATH TEXT --by user|me [--note N] [--date D]` and `noticed PATH
TEXT` add one line to Facts, Constraints, Decisions and Out of scope,
noticed (`constraint` strips one pair of outer double quotes from
QUOTE). A command that gives a new id prints it alone on its first line.
The user's words are traced to the user's own messages in the running
session's transcript (found from `$CLAUDE_CODE_SESSION_ID` under
`~/.claude/projects/`): `word`, `answer` and `decide --by user` without
`--take` are refused unless the user wrote after the item asked (a
session cannot give itself the word it waits for; a peer session's or
a delegate's message does not count), and the quote of `new --goal`,
`goal --quote` and `constraint` not found in a message of the user's is
warned of, exit 0, unless `--said-in WHERE` says where it was said
(stored, shown on the line). No transcript found: a warning, nothing
checked. `docs/journal.md`, section 4, has the rules.
`assume PATH "TEXT — how it will be checked" [--see F<n>,C<n>…] [--for
P<n>,O<n>…]` records an assumption, `A<n>` under *Assumptions:* after
Facts: what the plan takes as true without having checked it (unlike a
fact it is not verified, unlike a decision it is a belief, not a
choice), with what it rests on (`— see:`) and the pieces and questions
resting on it (`— for:`), open until a fact of the ledger settles it:
`assume PATH A<n> --confirmed-by F<n>` or `--refuted-by F<n>` (the line
ends `— by: F4`; settled once, `--reopen` first to settle it again),
`--for IDS` to replace what rests on it. While a piece in flight or an
open question rests on a refuted one, `check` fails
`assumptions-refuted`; one settled without its fact fails
`assumptions-settled`. The status line names the open ones, `assuming:
A2, A5`, and the resume view lists them with their check.
`criterion PATH D<n> (--met EVIDENCE | --unmet WHY | --unmark | --text
T)` marks a criterion `[x]` with evidence or `[-]` with why, takes the
mark back to `[ ]` (`--unmark`, its evidence or why cleared), or
rewords it, and
`criterion PATH new --text T` adds one; `edit PATH ID --text T` rewords
a fact (its pointer with `--pointer`), assumption (its text), constraint, decision, question detail or noticed line (`Z<n>`),
or the latest Goal's title, In short and Context (`edit PATH goal
--text T --short S --context C`, any of them; the quote stays the
user's); a piece's detail is
`piece --what`'s. `choice PATH O<n> --add "LABEL = effect; cost"` or
`--drop LABEL` changes the options of an open question under the grammar
`ask` keeps (refused, nothing written, for a label too long or holding
`;` or `?`, a duplicate label or effect, a question left failing
`open-picker`). `renumber PATH OLD NEW` gives an item an unused id of
the same kind; every structured reference follows by key, free prose is
never rewritten, and it refuses while the inbox holds an entry about OLD
not taken. `close` ends by listing the closed ledger's `Out of scope,
noticed` lines under `noticed, to carry: N`, and `new --carry CLOSED`
starts the new ledger with them. A second live ledger in a place (the
same directory or its `.claude/`) is a fork: `new` refuses it, naming
the live ones, until `--confirmed "the user's words"` is given, and the
new ledger then holds those words as a Decision by user.

An id is never reused: the counters live beside the events, so an
answered, dropped or undone item does not give its id back. Each writer
runs as one `BEGIN IMMEDIATE` transaction that records an event with
every row's before and after, and writes only when `check` on the result
fails nothing it passed before and names no failure on the item written;
it prints the line and the status line, `Status (TITLE) — criteria …`,
TITLE the latest Goal block's title (the ledger's address when none is
set), so that two live ledgers in one session are told apart. A second
writer waits for the lock and gives up with exit 2 after 10 seconds.
`--dry-run` on every writer but `new`, `take`, `close`, `mockup`, `waker`
and `purge` prints a unified diff of the `show` text and the status line the
change would give and writes nothing (exit 2 with the refusal when it
would refuse).

`piece PATH P<n> --status out` claims the piece for the session
(`CLAUDE_CODE_SESSION_ID`, or `--session ID`; refused without one);
another session's `--status out` on it is refused, naming the holder
and the time, and any other status clears the claim. `--status
verified` needs `--verified-by WHO` (`me`, the route that checked it, or
`peer: SESSION`). A piece out or back that goes back to `--status
planned` says why with `--cause brief|split|depth|contract|env` (the
brief lacked something, the piece was cut wrong, the tier or effort was
too low, the delegate broke the escalation contract, the environment
failed), refused without one and on any other change; `show PATH P<n>`
lists the returns, one a line. A session that takes over a piece another
left out runs `piece PATH P<n> --claim`: the claim moves to it, the
status stays out, and no return is recorded. Each dispatch of a piece
is announced with its ANNOUNCE block (the delegation skill's hook does
it): `piece PATH P<n> --announce FILE` (`-` reads stdin) stores the
block parsed (model, effort, highest axis and its level, the risk with
its `N/10` when the RISK line gives one, the mode and whether attended)
as a row of its own, a retry or an identical fan-out block included,
and prints `assessment recorded on PATH P<n>`; a block without the
ANNOUNCE line or one of WHAT, WHY, WHICH, RISK, MODE is refused, exit
2, the reason a sentence on the last line. The piece's line gains
`— dispatched: 2× (last: sonnet, medium, stakes low, risk 2/10)`,
`show PATH P<n>` lists each one with its time, and `undo` takes one
back like any write. When the delegate hands back, the same hook runs
`piece PATH P<n> --status back --handback`: a piece out goes back and
the one line `hand-back recorded on PATH P<n>` is printed; a piece in
any other status stays as it is, `P<n> is verified; the hand-back
changes nothing`, exit 0, so the ledger shows back, never further,
until the orchestrator verifies it; `--handback` with another status
or another flag is refused, exit 2. A piece built from the answer to a
question names it: `piece PATH P<n> --builds O<m>` (an open question,
one piece a question, `--builds none` clears it); its start is refused
while O<m> is open (`answer O<m> first`), and the viewer draws it on
the question's card, under the picker, its plan, risk and pictures
there and one button, `Answer and start P<n>`, which sends the answer
and, once it is accepted, the start (a start that fails then leaves the
card saying `Answered; the start of P<n> was not sent: REASON` with a
`Start P<n>` button that sends the start alone); the piece has no card
of its own while the question is open. The piece it replaces goes `piece PATH
P<k> --status obsolete --obsoleted-by P<n>` (refused on a piece out,
or when P<n> is obsolete or dropped): terminal like dropped, its line
ending its head with `— obsoleted by P<n>`, out of the live counts and
of `check --final`, in the viewer's record with its successor's chip in its head
and on its ties line. `show --json` gives each piece `builds` (`{question, decision,
text}`, the last two null while open) and `obsoleted_by`. `undo PATH` puts back the last event that changed the
ledger's items, in an event of its own, one level, refused once a row
changed since; the inbox's takes are never undone. `restore PATH --to
E<n>` puts back every item-changing event after `E<n>`; without `--to`
it lists the last ten events and refuses. `purge L<n> --confirmed`
removes a closed ledger made by mistake, its events and every row of its
items, from the journal: `L<n>` is the id `close` prints (and the dry run
shows), the only word that names a ledger that way for a write. The journal is
first copied with SQLite's online backup to
`journal.db.before-purge-L<n>-YYYYMMDD-HHMMSS` beside it (refused if that name
exists), then the rows go in one transaction, with the picture contents no
other ledger's picture shares; it prints the counts and the
backup path. Without `--confirmed` it prints the ledger's place, name, closed
time and the row counts per table and exits 2, writing nothing; a live ledger
or an unknown id is refused. It is irreversible: the purge is no event of any
ledger, so `undo` and `restore` cannot bring the ledger back; the backup is
the way back. `vacuum [--dry-run]` compacts the journal file: the write lock is first taken for an
instant with a 5 s busy timeout (refused with `another session is writing the
journal; try again` when it is not free, before anything is copied), the journal is
then copied with the online backup to `journal.db.before-vacuum-YYYYMMDD-HHMMSS`
beside it (refused if that name exists), `VACUUM` runs and the `-wal` is
checkpointed (`wal_checkpoint(TRUNCATE)`) so the file itself shrinks. It prints
the bytes on disk (journal plus `-wal`) and the logical size (`page_count` times
`page_size`) before and after, and the backup path. `--dry-run` prints
`page_count`, `freelist_count`, `page_size`, the logical size and the bytes on
disk, and writes nothing. Like `purge` it is no event, and the backup is the way
back. `gate-stamp` and `githook` (below, The gate stamp) take a git
repository's path, not a ledger's. The `self-routed` check fails
a piece in flight, awaiting no word, routed `peer:` to the ledger's own
project (the session that holds the ledger): keep it or route it to a
delegate.

## The hooks

Nine words of `ledger hook NAME`, each reading the payload on stdin,
writing no ledger, and turning any error of its own into exit 0. The
orchestration skill registers five in its front matter and
`session-start` in its `hooks.json`; `stamp` and `session-start` are
also what the waker needs, registered by the user (The waker, below).

- **heartbeat** (PostToolUse, Bash): when the command it ran names
  `ledger … check` or `ledger … status`, the last `Status (TITLE) —`
  line it finds in the output goes to the user as a `systemMessage`,
  its title naming the ledger. `check` also counts repeats: a line
  that has not changed since the last check is marked `unchanged ×N`.
  The count is kept on the ledger's row, not as an event, so an undo
  does not move it; `check --peek` reads without counting. A piece
  `out` with no event on it for 60 minutes (`LEDGER_STALL_MINUTES`
  changes the budget) is named `stalled:`. A piece ready to send
  (planned, awaiting no word, its `after:` pieces verified, kept or
  dropped) that has stayed planned for more than 2 hours
  (`LEDGER_READY_LIMIT`, in minutes, changes the limit) is named with
  its age, `ready, unsent: P65 (2 days)`; the resume view lists it
  under `Ready, unsent:`, the viewer's card says `ready, not sent for
  2 days`, and `stats` counts the unsent pieces per route.
  `piece P<n> --hold WHY` holds a planned piece back on purpose: the
  status line says `held: P22 (waits for P28)` instead, its line `—
  held: WHY` and its card `Held: WHY`; `--hold ''`, any other status,
  or every piece WHY names (`P<n>`) being verified, kept, dropped or obsolete
  clears it.
- **brief-constraints** (PreToolUse, Agent): reads the Constraints of
  the session's ledgers, and a brief that names a path one of them names
  (`vendor/`, `units/time.py`) without carrying it verbatim is refused.
- **brief-piece** (PreToolUse, Agent): with a live ledger in the session's
  place, a dispatch whose prompt has no header line `Piece: <absolute .md
  path> P<n>` between its BRIEF line and the first blank line after it is
  refused, as is one naming a piece that is neither ready nor out and
  claimed by the dispatching session (a
  relative or non-`.md` path is refused naming what was found). `Piece:
  none — WHY` lets a delegate that is no piece through. A dispatch that
  writes (unless its `Tools:` header is Read, Grep, Glob alone or its
  `Permissions:` say read-only) and has no `isolation: worktree` is
  refused, naming the piece, while another piece is out with a writing
  dispatch this hook let through (kept in `dispatches/SESSION_ID` beside
  the journal); readers always pass. No live ledger: it passes silently.
- **journal-write** (PreToolUse, Bash): refuses a command that writes
  the journal file, or its `-wal` or `-shm` companion, by hand: `sqlite3`
  on it without `-readonly`, `>`, `>>`, `tee`, `cp`, `mv`, `rm`,
  `install`, `sed`, `perl` or `ruby` in place, or interpreter code that
  opens it. A hand write skips the write path: the check that the ledger
  is no worse after it, and the events `undo` and `restore` read. A
  command whose program is the launcher passes, a `sqlite3 -readonly`
  read passes, and the refusal names the `bin/ledger` commands to use.
  It reads the words of the command, quotes respected, so a quoted
  message that mentions a write passes.
- **finish** (Stop): when a ledger has a piece, no piece is planned,
  out, back or blocked, and nothing waits on the user (Open empty, no
  word owed), a stop whose ledger fails `check --final` is sent back
  once with the FAIL lines and the finish steps. A turn that ends to
  wait is never refused: a ledger whose only failure is its deferred
  pieces waits on their event as it would on the user, and its stop
  goes through. So does one that fails besides only on criteria
  unmarked, each served (`for:`) by deferred pieces among its
  unfinished ones or by no piece at all: they wait on the same event.
  A criterion met without evidence or not met without why, or any
  other rule failing, still sends the stop back; `check --final` itself
  still fails. The retry is let through
  whatever it did.
- **inbox** (Stop): pending viewer entries refuse the stop once,
  verbatim, with the filing steps.
- **status-stop** (Stop): when the session's ledger has a piece out or
  back and its status line differs from the last one this hook showed for
  the session (kept in `status/SESSION_ID` beside the journal file), the
  line is printed as the hook's `systemMessage`, the text `check --peek`
  gives. It never blocks: exit 0, nothing when unchanged or without a
  ledger.
- **one-list** (PreToolUse, TaskCreate|TodoWrite): while the session has
  a live ledger, a task list is refused, the reason pointing to
  `bin/ledger piece PATH new ...`. A call whose payload carries `agent_id`
  (made inside a subagent) passes; with no live ledger it passes.
- **viewer-guard** (PreToolUse, Bash): refuses a command that starts or
  stops the viewer or the waker (`ledger-viewer`, `ledger-waker`,
  `rake server:start`, `rake server:stop`), also through `bundle exec`,
  nice, timeout, low-priority, env, nohup, `sh -c`, `eval` and a path to
  the bin: the user starts and stops them; a session restarts the viewer
  in place (`rake server:restart`, which passes). A command that only
  names a program (grep, echo) passes. Stdlib only.
- **edit-record** (PostToolUse, Edit|Write|NotebookEdit): appends the
  absolute path the tool edited to `edits/SESSION_ID` beside the journal
  file (`LEDGER_JOURNAL` moves it), one path per line, no duplicates.
  It answers nothing; the standard library alone, no bundle.
- **commit-record** (PostToolUse, Bash): after a command naming git, a
  HEAD that moved since the session last saw it in that repository
  (the first sight only remembers; kept in `heads/SESSION_ID` beside the
  journal) gives the commits `old..new`. They are attached with `piece
  --commits` to the one piece whose commit word this session filed and
  that holds no commit, else to the one piece awaiting commit; when no
  one piece is meant, one line names them so the session files them.
  Never blocks; silent when nothing moved. `check --final` warns of a
  piece given its commit word that holds no commit.
- **word-gate** (PreToolUse, Bash): in the main session (no `agent_id`),
  a `git commit`, `git merge` or `git push` in a project with a live
  ledger is refused without the user's word on file, also through nice,
  timeout, low-priority, env and `sh -c`. A commit, and a merge that
  lands something (`HEAD..BRANCH` not empty), need a piece given its
  commit word that holds no commit yet; a push needs a piece given its
  push word after the last push the hook let through for the repository
  (kept in `pushes` beside the journal). No live ledger, a delegate and
  any other command pass silently.
- **uncommitted** (Stop): the recorded files a git repository still
  shows as changed (`git status --porcelain -- PATH`), in a repository
  whose project has a live ledger where no piece awaits commit, none
  is out and none carries `--no-commit WHY` (deliberate scratch work), are sent back once as `files you edited are uncommitted and no
  piece awaits commit: PATHS; file one with --awaits commit ...`. Once
  per distinct set of files (its digest is kept in `edits/SESSION_ID.sent`),
  and the retry (`stop_hook_active`) goes through. Without a record or a
  live ledger it passes.
- **session-start** (SessionStart): the entries waiting at the start,
  and on a start, resume or compaction the resume view of the session's
  ledgers. First it records the session for the waker: its id, its
  messaging socket's path (`CLAUDE_CODE_MESSAGING_SOCKET`; the token
  beside it is never read), its directory and its ledgers.
- **stamp** (Stop): the turn's end in `session_stops`, the waker's test
  of idle. It starts without the bundle and writes through the
  `sqlite3` program (`/usr/local/bin/sqlite3`, `LEDGER_SQLITE`
  overrides).

The session's ledgers are the live ones whose address is directly in
the session's directory, its `.claude/` or its scratch directory.

## The viewer

The status line reaches the user only when a session runs a check.
`bin/ledger-viewer` (or `rake server:start`; `rake help` lists the rest)
serves every live ledger of the journal, a Sinatra app on Puma listening
where `config/app.rb`'s `bind` says (`tcp://127.0.0.1:4590` by default).
Callers sign in (sesam: a password, from an invitation that
`rake user:invite NAME=…` prints once), except those on a network the
`lan` setting names, none by default. The index is one queue
of what waits on the user across every ledger, oldest wait first, under
a summary that leads with what exists ("4 words to give · 2 to review",
a zero left out). A row is the id and the title of the question or the
piece in bold, a muted line "ledger · question" or "ledger · awaits
commit, deploy" (with " · risk N/10" when it is rated), the wait when a
time is known, and a link that opens the card: *Answer*, *Review WORD*
(*Open* for an `other` word), the id in its accessible name. A ledger
named `LEDGER-SFX.md` shows as `project · SFX` wherever its name does.
Then the sessions' turn (answers sent and not read by the session yet,
each named by its title, then ledger and id; questions being prepared)
and a table of the ledgers, each with its state in words (*awaits*, then
the words still owed, counted, then how many are sent; an
`other` word's need on a line under its row), its changed time under
its name, narrow enough for a phone. A ledger page has the questions as
a list beside it when the page is wide enough for both (waiting on you,
sent, being prepared, then the other sections), above it otherwise;
what waits on the user (questions to answer and words owed) is in one
order on the page, the index queue's, the oldest wait first: the head's
next step names the first, Waiting on you and the side list list them
in that order, and a receipt's next card follows it;
each option of a question is a tile with what it does and costs, and
each card after Send offers the next question. The note box sits under
the Goal, folded; "Leave a note" opens it. The Goal section shows every
block not done, newest first, each headed by its `G<n>` chip, with its
title, its short line and its context, the user's own words folded under
them (open when the block has neither title nor short); the done blocks
are folded under *Done goals · N*, newest first, each with its
evidence. On top of the page, the ledger's name with the newest
active goal's short line under it, the next step as the head's one
filled button ("Answer O1: …"), "Leave a note", then the settings that
are not the work folded under *Details*, whose summary says their state
(`Details: waker off, batch off`): the path and the session's status
line, without its title (the page names the ledger), the waker's
switch, the batch switch and *Abandon the ledger*. Then what remains
(questions to answer, answers sent and not read by the
session yet, questions being
prepared, criteria not met straight under the Goal, unfinished pieces
with a fold to propose their order, failing shape checks) with what is
done folded below. A planned or deferred piece with nothing to say yet
(no problem, risk or plan, no word awaited, no picture, no issue such
as returned, stalled or ready and not sent, nothing sent on it) is one
row under Unfinished pieces (title, status, id, the links
icon) that opens into its card; a link to `#piece-P<n>` opens it. Out,
back and blocked pieces, and any with something to say, stay cards; a
blocked piece says what blocks it straight under its title. A piece
out or back shows its gates as chips (`unit failed`, coloured by
state, the time on hover), the detail of the last one failed under
them, and its helper's report folded (*Report: DONE_WITH_CONCERNS*);
once verified it shows neither, and `show PATH P<n>` keeps both.
Every piece card (in flight, waiting on a word, on record) and every
question card carries a RAID line under its case, each part left out
when it has nothing to say: the risk (its ten-step meter; on a piece
the work risk, `work N/10`, the rated RISK of its last dispatch once
it was dispatched, else its own `--risk`, a kept piece's among them,
the number Waiting on you sorts and filters by; or *no risk
rated* for a piece in flight, unless it is planned or deferred and
awaits no word), the assumptions it rests on (`rests on
A1 (open), A2 (refuted)`, each chip leading to its row), its issues
(`blocked`, `stalled 2 h`, `returned 2: depth, unrecorded`) and what it
depends on (`serves D2`, `answered by P5`, `see F2`).
Under the head of every piece card and open row, one ties line says what
it is tied to in id chips, each part left out when empty: `waits for`
(a settled piece muted with a tick, an unsettled one with its status on
hover; the line opens with `ready —` on a planned piece whose waits are
all settled), `needed by`, `obsoletes`, `obsoleted by` and `builds` (the
question it builds); each chip links to where the page draws the item,
and an obsolete row carries its successor's chip beside its status.
The record opens with a fold titled *Risks, assumptions, issues,
dependencies (n)*, four lists: Risks (every rated
one, highest first), Assumptions (open first, then confirmed and
refuted, each with its check, what it rests on, what rests on it and the
fact that settled it; then the decisions by me, the session's
reviewable judgements, each with what it rests on), Issues (open
questions, blocked and stalled pieces, failing
checks, noticed lines) and Dependencies (each after or by piece not
settled, each deferred condition). A stalled piece says so in the side
list too (`out · stalled 2 h · with sonnet`).
A question already answered counts as the session's turn, not the
user's. Every request reads the journal. When its ledger changes (any
ledger, for the index), the page shown fetches itself again and draws anew only the parts the
server now draws differently: on a ledger page the head, the cards, the
section counts, the side list, the record folds and your messages; on
the index its rows. The page does not move and the focus stays, and a
fold keeps its open state. A part you hold (a form in it differing from
what the server sent, the focus in it, its picture open, or an item of
the tray from it) is left as it is and says *Changed since you started*
with an *Update* button, which draws it anew and puts back what was
typed or chosen where its field still is. A change outside those parts
(the goal, the note or the order form, a section coming or going), or a
page that cannot be fetched, falls back: the index reloads itself
unless a form differs from what the server sent, a box is being typed
in, or a mockup is open, and a ledger page says *Ledger changed* with
a *Refresh* button, which reloads and returns to the same scroll
position and open folds, and puts back what was picked or typed in an
answer form and not sent (kept in `sessionStorage` per ledger and item,
a line on the card saying so; a choice no longer offered is said,
nothing sent). When the live stream has been down for 10 seconds, a
quiet *Live updates paused* status shows in the page head until it
returns; the 3 s poll runs meanwhile. The user starts it; no hook does.

A ledger page reads, top to bottom and in the tab order: crumbs, the
title, the goal's short line, the next step (the id, then `Your word:
TITLE`, the words as icons and in text), *Details* folded, the tiles
(Waiting on you, then Criteria, which links
the met-criteria fold once all are met, and Work verified; Unfinished
pieces only when some are; they share each row), Waiting on you, the side
list folded as *Sections of this ledger*,
then the Goal with the user's words folded and the criteria not met
under it. With room (64 rem) the side
list stands beside, Waiting still above the Goal, and both folds are
open; the page script keeps each fold's own state for a narrow page. A
*Skip to waiting work* link comes first and shows on focus. A
criterion's serving pieces are counted (`16 pieces: 15 verified, 1
kept`), their links folded; the section of what was sent is *Sent,
not read by the session yet*, the filed ones *Filed (N)*.

A piece and a question open with a short title in words (at most 60
characters, before the first `: `) and the detail after it: the card's
head shows the title, the detail under it; the side list, the index
queue and the "Answer O1: …" link show the title alone. `check` fails
a longer title on a piece in flight or an open question (`titles`);
settled pieces keep their lines. The detail fails the same check when
ids outnumber words two to one (`details`); codes are named with
`— see:`. A code whose letter is not one of the ledger's kinds (`W1`
from another note) fails `codes` wherever it stands alone in item text,
unless an open question's `— see:` names an item that holds it; the
user's words in double quotes and `` `code` `` are not read.

Ledger text is rendered as the small part of Markdown it uses, on the
server, from text escaped first: `**bold**`, `*italic*`, `` `code` ``,
`[text](https://…)` and bare https links everywhere; paragraphs, `-`
and `1.` lists, `>` quotes and fenced code in the Goal and the inbox
entries. No HTML written in a ledger reaches the page, and no script
library has to be trusted to sanitise it. `$…$` is left as written.

What the page takes, all as inbox entries, of the four kinds
`Ledger::Hooks::Entry::KINDS` names (read from an entry's `ref`: none,
`O<n>`, `P<n>`, `order`), the one list `inbox` and the hooks use:

- **An answer** to each open question, which carries its case:
  `— problem:`, `— risk: N/10 — …` (rated 0 to 10, shown on the card's
  RAID line as a meter coloured by band), each option `X = what it does, what it
  costs`, and `— recommend: X, why`, shown as labelled rows under the
  question's title, the recommended option marked. `check` fails a
  question without its problem and risk, or, once it can be answered,
  without described options and a recommendation (`open-described`).
  A piece carries the same `— problem:` and `— risk:`, and a
  `— plan:` (what the session will do), shown under its head; one
  awaiting the user's word must give the first two (`piece` refuses
  it otherwise), and the journal refuses a rating outside 0 to 10.
  A question that offers its
  answers (`choices: a | b`) gets one button per option, a comment box
  per option and an overall one; the entry carries `choice` and
  `notes`, and the server refuses an option the question does not
  offer. With `— items: x | y` it gets one row of options per item and
  a comment per item; the entry carries `picks` ({item: option}) and
  `notes` by item. The ledger items a question names with `— see:
  F2, C3` are spelled out under it, in a fold; ids are never guessed
  from its text, where a review's own "C3" would read as Constraint C3.
- **Nothing**, for a question still being prepared: one whose `by:`
  piece, or the piece drawing its `mockup: pending (P<n>)`, is not
  verified (or kept). It is listed under *Being prepared* with the
  piece and its status, no form, and the server refuses an answer to
  it; the status line names it `being prepared: O9 (P36)`, and its wait
  starts only once it can be answered. When that piece is deferred the
  card says *Waits for P36, deferred until CONDITION* instead of that
  the piece is still preparing. A question whose `by` piece awaits the
  user's word (a loop `check` reports as `question-loop`) is not
  waiting for it: it is drawn answerable, with its picker, and its meta
  line says *P36 waits for your start; this question can be answered
  now*.
- **A comment on a question**, not an answer (to ask for more before
  answering): below an open question's answer form, a fold *Ask about
  O<n>* with its own *Send question*; the entry carries `comment: true`
  and the text, and the server refuses it empty or once the question is
  no longer open. It replaces nothing, and an answer sent after it need
  not name it; the card stays a question to answer, with *asked: N<n>,
  sent HH:MM · not read by the session yet* until the session takes it, and only
  that line and the fold are redrawn when it is sent with `fetch`.
  `ledger inbox` shows it as *comment on question O<n>, not an answer*.
- **A picture asked** of a card that has none: a question with no
  mockup placed and none pending, or a piece (under Waiting on you or
  Unfinished pieces) with neither its before nor its after placed,
  offers a fold *Request a picture*: the kind (*any*, the session picks
  the cheapest that settles it, first and selected; *text*, a text
  figure; *svg*; *screenshot*; *page*, a working web page) and *What
  should it show?*, sent by its own *Request picture*. The entry is on
  the card's id and carries `picture` (the kind) and the text; the
  server refuses it empty (400), of a kind not in that list (400), or
  once the id is no longer a card on the page (409). It answers nothing
  and gives no word: it replaces nothing, and an answer or a word sent
  after it is taken as before. Until the session takes it the card
  says *picture asked: N<n>, sent HH:MM · not read by the session yet* and offers
  no second fold; on a card under Waiting on you only that part is
  redrawn when it is sent with `fetch`. The session files it by drawing the picture and
  placing it with `mockup --question O<n>` or `mockup --piece P<n>
  --before|--after`, then taking the entry. `ledger inbox`, the Stop
  hook and *Your messages* show it as *picture asked for O3 (svg)*.
- **A comment on a planned piece**, before it goes out, and with two or
  more planned, **a proposed order**, refused unless it names each
  planned piece once. With script the order is a list of the pieces'
  titles, each with up and down buttons (44 px targets) that rewrite
  the comma field below it; the field stays, and is the whole form
  without script.
- **A word on a piece** the ledger says awaits one (`— awaits: start`,
  on a planned or kept piece; `commit, deploy`, `other (what)`; the
  words are start, commit, deploy, push, merge): its card under Waiting
  on you reads problem first (head, problem and plan, its RAID line,
  then *What it covers* folded) and has
  a button per word, the one for all of them filled and first (no click
  is the wait); the entry carries `word`, and the server refuses a word
  the piece does not await. A piece may carry `— scope: commit = what it
  authorises | deploy = …` (`piece --scope`, only for words it awaits,
  pruned as words are given), shown under each word's button. Each
  button carries its step risk, a meter `step N/10` under it: what the
  word itself puts at stake, start 0, commit 1, merge 2, push 4,
  deploy 5, 3 more on a piece `--irreversible`, capped at 10; the
  combined button the highest of its words, `other (what)` none. The
  piece's evidence, when it has one, sits just above the buttons, with
  a link to its row in the record. The
  comment folds below the words with its own *Send comment* and
  *Quote selection*, named *Comment on P<n>*. An answer or a word
  is sent with `fetch` when the page has script: the answered card is
  swapped in place for its receipt, collapsed to one row with *Change*
  (a view transition), then the page scrolls smoothly to the next card
  waiting, which takes the focus and pulses once; the head's next step,
  the tiles, the side list and the Waiting count are redrawn from the
  same answer (a change by someone else in it still shows *Ledger
  changed*); *Change* opens the
  card again where it stands; with reduced motion the same happens
  without transition, smooth scroll or pulse. While the send is out the
  pressed button reads *Sending…* (disabled, `aria-busy`) and the card's
  other submit buttons are disabled; drafts elsewhere stay editable, and
  everything returns on the answer, a refusal or *Delivery unconfirmed*.
  While the waker is off and sent entries are unread, the ledger head
  says *N sent, not read yet — no session is woken while the waker is
  off*, with a *Switch on* button (the waker's own form,
  `POST /l/ID/waker`), and redrawn with the head.
  A send that leaves nothing waiting on the user ends the receipt with
  *Nothing left waiting on you in this ledger* (`role="status"`), which
  takes the focus, *not read by the session yet* staying visible. A refusal, a failed fetch
  or a card that did not become a receipt falls back to the plain form
  post. Without script the send answers 303 to the next card waiting
  (`#p-P<n>`, `#q-O<n>`), to the answered card when none waits; a
  comment, a note or an order goes back to its own card or `#inbox`. A
  piece whose word is sent shows a receipt, *You asked: Commit + Deploy
  · sent HH:MM · not read by the session yet*, then a link to the next card waiting
  or *Nothing left waiting on you in this ledger*. When two or more pieces wait and all
  await the same words (none `other`), a bar under the Waiting heading
  gives them all in one request (`POST /l/ID/say-all`: token, Origin and
  Host as `/say`; refused with 409, sending nothing, if any no longer
  awaits exactly those words): one word entry per piece. Any piece in
  flight can also be dropped, as a request: a trash icon (a 44 px
  target) in its title opens a fold *Ask the session to drop P<n>
  without follow-up*, what it does, an optional reason, *Cancel* (back
  to the trash) and *Ask to drop P<n>*, the one red button, sending the
  word `drop`. Questions have the same icon, to drop (ignore) one; so a
  question never offers drop or ignore among its choices (`check` fails
  it, save per item).
- **The tray**, for sending several things at once. *Batch mode*, a
  switch the script draws in the head's *Details* fold, is off by default and
  kept per ledger in the browser (localStorage; without it the switch
  and the tray last as long as the page). While it is on, a word on a
  piece, a comment on a piece or a question (*Ask about*) and a drop of
  either go into the tray instead of being sent: the card says *Word
  commit in the tray* (*Comment*, *Drop*) with *Remove*, its form
  closed as after a send. Each button whose act goes to the tray says
  so while batch mode is on (*Commit to tray*, *Send comment to tray*,
  *Drop P2 to tray*). Answers, notes, Close, Abandon, pictures
  asked and the order are still sent at once, and an answer form says
  so above its Send. A bar sticks to the page's foot
  while the tray holds something: *N in the tray*, each item's id, kind
  and text cut at one line with its *Remove*, then *Send all (N)* and
  *Empty tray* (which asks again inside the bar). *Send all* posts the
  whole tray in one request (`POST /l/ID/say-batch`: token, Origin and
  Host as `/say`, `items` the JSON list of the forms trayed); each item
  is checked by the rules of its own send, in the tray's order, an item
  seeing those before it as sent (a second word on one piece is refused
  as it would be after the first), and all are filed in one write, one
  `inbox` event, each its own `N<n>`. One item refused and nothing is
  written: the answer, JSON, names each refused item with its reason
  (400 when any is malformed, else 409), the tray keeps them all and
  marks those. Sent, the tray empties and the cards, the head's next
  step, the tiles, the side list and the Waiting count are drawn again.
  The tray is kept per ledger across a reload; an item whose card is no
  longer on the page says so in the bar, and *Send all* waits until it
  is removed. Batch mode off, everything is sent at once as before.
- **The close of the ledger**, only while its status line ends with
  `done: propose close`: the head reads *Ready to close.* and offers
  *Close the ledger*, a fold that says what closing does, takes an
  optional comment, and sends only with *Yes, close it* (*Cancel* folds
  it back). The entry has `ref` `close`; the server refuses it, 409,
  once the status no longer proposes the close, which it stops doing
  as soon as any entry waits, the Close sent before among them. Sent,
  the head shows *close asked* with its receipt until a session files
  it with `ledger close PATH --take N<n>`, closing the ledger and
  taking the entry in one event; a close refused takes nothing. With
  every criterion marked, no piece in flight and no question open, the
  Remains section says *Ready for `bin/ledger close`* only when the
  Close is offered; otherwise it says what the status line holds the
  close on: *Not yet: an entry from you waits to be filed (N1).*, or
  *`bin/ledger check --final` still fails* when the line names nothing.
- **The abandon of the ledger**, on any live ledger, after the Close
  when the Close is offered, inside the head's *Details*: *Abandon the
  ledger* (its own icon, not the trash), a fold that says what
  abandoning does (the pieces not finished dropped, the open questions
  closed, the history kept), takes an optional comment, and sends only
  with *Yes, abandon it*, the red button. The entry has `ref` `abandon`;
  the server refuses a second, 409, while one waits to be filed. Sent,
  the head shows *abandon asked* with its receipt until a session files
  it with `ledger close PATH --abandon --take N<n>`.
- **A note** per ledger.

Every box has a *Quote last selection* button, hidden until text on
the page has been selected: it goes in as a `>` quote, a blank line
after it, so several quotes and comments leave as one entry; the
button sits under the box it fills, in a row of its own, so Send stands
alone. A question's choice is required: Send is refused with none
picked, and a choice whose text says `in your comment` opens its
comment on being picked, says what to write there and requires it.
Every option keeps its comment fold; text written in the comment of an
option that is not the one picked says *This option is not your
choice* beside it, and is still sent with the answer. A
card's status is one pill that opens, on a tap, to what the status
means after the word, in the same pill; an
item id is drawn in two halves (the letter pale, the number on the
chip's own colour, in gray when it has none) so the letter O differs
from the digit 0 in any
font; the trash says *Drop* beside its icon where the card is narrow.
The overall comment on a question folds until wanted, a recommended
option carries its reason under its label, and Send names what it
sends ("Send answer to O1"). A question answered and not filed yet
shows the answer sent; *Change your answer* opens holding it, and
sends as "Replace answer to O3". A question shows how long it
has
waited, from the events (a question's wait starts when it is asked, or
when the piece preparing it is settled, whichever is later; a word's
when its piece began awaiting it, keyed `P<n>:word`), a word row and a
word card too, the index the longest wait, and a question an entry
answers but no session has
filed says so. A piece's optional `— done when: …` shows under it.
Under Waiting on you, *Answered today* lists each question whose Decision
line is dated today (id, the quoted choice, a link to that line); a
Constraint (`C<n>: "quote" — where (note)`) and a Fact (`F<n>: claim —
source`) are drawn as id, words and a muted source line, a line that does
not parse as written. The Decisions fold is drawn the same way under one
small heading per date, newest first (`today` for today): a line
`DATE — [O<n>: ]what — why — by user|me (note)` is the id chip, the
words, then a muted line with the why parts, `your call` (by user) or
`the session's call` (by me) and the note; a line that does not parse
keeps the plain row, and every row keeps its `dec-N` anchor.

A question that needs a look names its picture on its Open line,
`mockup: NAME`, a picture in the journal. The page shows an
image or an HTML mockup (in a sandboxed frame) as a thumbnail tile,
15rem wide, in a strip under the question: tapping the thumbnail opens
it full size, like *Expand* below. The strip wraps on a wide card and
is one row scrolling sideways on a narrow one. A picture named
`before-NAME` pairs with the image or page of the same ledger named
`NAME` (one leading item code such as `m1-`, and the extension, are not
part of the match) as one tile of two thumbnails, *Before* and *After*;
the pair sits at the after-mockup's place. On a question answered per
item, a mockup whose name starts with the item's code (`m1-…` for item
`M1`, case-insensitive) is drawn inside that item's group instead of the
strip. Page thumbnails render the page 64rem wide (1024 px at the
default size) scaled to the tile. The answer box comes under it. A
picture belongs to one ledger, and a
ledger shows only the pictures its questions name.

`bin/ledger mockup PATH FILE|DIR... --question O<n> [--name NAME]`
places them. The files are read into the journal as `pictures` rows (the
bytes as they are, with the content type the viewer serves; each distinct
content stored once, so a file placed again costs no bytes), whatever
directory or worktree the command runs in, so a peer drawing in a
worktree lands it in the ledger it names; nothing is written on disk. A
FILE is stored by its name, a DIR as one name with a row per file, its
CSS and images under it. Every FILE or DIR of one call is named on the
question, in the order given (`--name` is for a single FILE or DIR, and
is refused with several). A DIR is drawn by one of its files, the same
pick in the command and in the viewer: its `index.html` at the top, else
its single page (`.html`, `.htm`), else its single image or SVG; the
question's `mockup: NAME` keeps naming the directory, and the page's
relative CSS, scripts and images are served from the directory's other
files. A directory with several pages and no `index.html` (or none of
these) is refused by the command and, if the journal holds one, flagged
in the card instead of drawn. The first kind present decides: two pages
and an image are several pages, not the image. A directory holding only
a `.txt`, and a single FILE that is not a page, image or text (a
stylesheet placed alone), are refused. Before anything is stored it refuses a kind the
viewer would not serve (`Ledger::Pictures::TYPES`), a symlink, a name
`mockup: NAME` cannot spell, a name the ledger already placed, a missing
or unknown question, and a name that opens on nothing. On the
question, `mockup: pending (P<n>)` becomes `mockup: NAME` (the first
name placed), else ` — mockup: NAME` is added for each name. With `--replace` every picture of the question gives way to the
one new picture: a swapped picture, not a second one (the old files stay
in the journal). The change is an event, checked like any write: `undo`
puts the question's pictures back, the blobs staying. Besides a page or
an image, a mockup may be an illustration: an SVG, or a text figure
(`.txt`, ASCII art or a diagram) drawn monospace in the card, unwrapped,
at most 64 KiB; one longer than 15 lines is a tile too, its thumbnail
the first 12 lines. Each picture has *Expand*, which opens it in a pane
beside the page when the window is at least 64rem wide and in a window
over it otherwise (Esc or *Close*), and *Open in a new tab*; the page
does not reload while one is open. A mockup may load its
own CSS, scripts, images and fonts from the files it was placed with,
and nothing else. A frame in an opaque origin sends no session cookie,
so a page signed in to the viewer draws its mockups from
`/m/k/TOKEN/LID/NAME`: the files reach a frame through a short-lived
signed path, good for an hour and for that one ledger, which the page's
relative CSS, scripts and images inherit; a bad or expired key is a 404,
and the plain `/m/LID/NAME` stays behind sign-in. Its pages run in an
opaque origin, by a `sandbox` CSP that holds even when one is opened
on its own, with no fetch, no form and no frame, so a mockup can
neither read the viewer's token nor post to it.

A question with several options can give each its own picture, an
after for each choice: `bin/ledger mockup PATH FILE --question O<n>
--choice LABEL` places one FILE (or DIR) as that option's picture, one
per option, `--replace` swapping it. The label is folded as `choice
--drop` folds it; one the question does not have is refused naming the
labels it has, as is an option that already has its picture without
`--replace`. An option's picture is drawn as a thumbnail inside its
tile, under its text and above its comment fold, the whole thumbnail a
button that opens it full size like any mockup; the question's own
picture, when any option has one, is labelled *Before*. A question
answered per item (`--items`) keeps its options as plain buttons, so
`--choice` is refused on it: place one picture for the question. Dropping an option (`choice --drop`) takes
its picture link away, the blob staying; `show` prints it after the
option, `— picture: NAME`. `check` warns on a plain check, never on
`--final` and never refusing a write, of an open question where some
options have a picture and others none, `pictures-options`, `O19: no
picture for options A, C`.

A piece awaiting commit, deploy, push or merge shows what the word
changes: `bin/ledger mockup PATH FILE --piece P<n> --before` (or
`--after`) places one file as that side, and its card under Waiting on
you draws the pair as one tile, *Before* on the left and *After* on the
right (on a card narrower than 36rem, a phone's, *Before* over *After*
at the card's width), each opening full size; a side already placed is refused unless
`--replace` takes it away (its blob stays). A piece with nothing to
show says why with `bin/ledger piece PATH P<n> --no-picture WHY`, drawn
on its card as a muted line `no picture: WHY`. `check`'s `pictures` rule
fails such a piece with neither both sides nor a reason, so the write
that makes it await the word is refused until one is given; `start` and
`other (…)` ask for none. `undo` takes a placed side back.

A picture shows its item as it was when placed. `check`'s
`pictures-fresh` rule names each item whose words were reworded since: a
piece with a picture whose plan, detail or problem now differs from what
it held when its latest picture was placed, an open question with a
picture whose detail, problem or choices (one added, dropped or
reworded) do. A field first set after the picture is no change, and a
rewording taken back (`undo`) is none either; status, evidence, risk,
links, awaits and route never count. The line names the item, the
fields and the picture's time, `P81: plan, problem changed after its
last picture (2026-11-22 09:45)`. It is a `warn` line on a plain
`check`, leaving the exit status as it is, and a failure on `check
--final`. While the picture is redrawn, `bin/ledger piece PATH P<n>
--picture-pending WHY` says so: a plain check announces the piece
(`P81: picture being redrawn (WHY)`) instead of warning, `--final`
still fails it until the redraw, its line in `show` ends `— picture:
being redrawn (WHY)`, its card draws the muted line `Picture being
redrawn: WHY` in place of the before/after, and the next `mockup
--piece P<n>` clears it (`--picture-pending ''` by hand). When the
picture still shows the piece after a change, `bin/ledger piece PATH
P<n> --picture-holds WHY` says so: the check then measures from that
write instead of the last picture, so a later rewording makes it stale
again, and its line ends `— picture: holds (WHY)`; one write never
carries both flags. A write that leaves a piece stale, awaiting commit,
deploy, push or merge and not being redrawn is refused; it passes with
`--picture-pending WHY` or `--picture-holds WHY` in the same write, or
once a new picture is placed.

It writes inbox entries, never a ledger's items: under each open
question an answer box, and one note box per ledger, each send filed
through `Ledger::Inbox.append` as one `inbox` event, actor
`viewer:<user>`, its entries numbered `N<n>`. The ledger's items keep one
writer, the session; the inbox has one, the viewer, and both go through
the journal's write lock, so a session and the viewer at once serialize.
In a request the viewer waits at most 2 s for the lock and then answers
503. `ledger hook inbox` refuses the session's next stop once with
the pending entries verbatim; the session files each in the ledger and
records it with `ledger take`, and the page turns it from awaiting
filing to filed. An idle session runs no hook, so an entry waits for its
next turn, unless the session watches the inbox: `ledger inbox PATH
--follow` prints each entry once as it becomes pending (already pending
ones first), `--wait [--timeout S]` blocks until one is pending and
prints them (exit 1 on timeout); both look at the ledger's newest event
id every second, read only. The `session-start` hook shows the entries
waiting at the start; the status line names pending entries (`from the
viewer: N1`), and `close` refuses while any is pending.

```text
 ┌─────────┐ POST ┌────────┐ inbox event ┌─────────────────────────┐
 │ browser ├─────▸│ viewer ├────────────▸│ journal (inbox_entries) │
 └─────────┘      └────────┘             └────────────┬────────────┘
                                                      │ Stop: hook inbox
                                                      ▼ relays them
                                         ┌─────────────────────────┐
                                         │ session files them,     │
                                         │ then ledger take        │
                                         └─────────────────────────┘
```

A POST puts words in front of a session as the user's, so it needs a
signed-in caller (or one from a `lan` network), the form token (derived
from the session and the server's secret, so a restart of the server
does not void the pages already open, and a page of another site cannot
name it), an Origin naming the viewer, and a Host `bind` permits; an
answer must name an `O<n>` still asked. A send whose token no longer
matches is refused (403), and the refusal page shows the text back in a
form carrying the current token, so nothing typed is lost. The rest
stays read-only: a ledger named by a hash of its address rather than by
a path from the URL, the text escaped, and the journal read through
`Ledger::Read` rather than `check`, so viewing never moves the stall
counter. No command files an inbox entry, and the `journal-write` hook
refuses a session's hand write, so a session cannot write one as the
user. On the network, sign-in is the authentication: name a `lan`
network only where every device on it is the user's.

The viewer is pushed changes over server-sent events (`GET /events`): a
page draws its changed parts anew, or falls back to the note or the
reload, within about a second of a ledger write. The 3 s poll of `/stamp`
remains as the fallback, slowed to 30 s while the stream is open. Both
take an optional `lid`: a ledger page passes its own and watches that
ledger's stamp alone, which its `data-stamp` carries too, so a write to
another ledger leaves it untouched (a ledger closed or unknown answers a
stamp no live ledger has); the index passes none and watches every
ledger's. A sent
card reads `sent HH:MM · unfiled for N min`, a filed entry reads `filed
at HH:MM` (the take event's time), and the header reads `Ledger updated
today HH:MM` (the ISO date instead of `today` when it is not). Times
are local, 24-hour.

```text
 bin/ledger-viewer
 rake user:invite NAME=alice
```

## The waker

An entry the user writes in the viewer reaches a session at its next
Stop or start. A session sitting idle never gets there, so
`bin/ledger-waker`, a foreground loop the user runs as they run the
viewer, rings it: once a minute, for each ledger switched on with an
entry pending, each session of its directory whose last turn ended more
than 10 minutes ago (`LEDGER_WAKER_IDLE_MINUTES`) gets one line naming
its ledgers, and nothing else:

```text
ledger: an entry from the user waits on ADDRESS; run ledger inbox ADDRESS
```

- **The switch**: off by default; `ledger waker PATH on|off`, or the
  switch under the ledger page head's *Details*. One `waker` event, which undo takes
  back.
- **Idle**: the session's last `stamp` older than the idle minutes, no
  wake since, and `claude agents --json --all` listing it `idle`
  (interactive) or `done` (background), or not at all. `busy`,
  `blocked` and `failed` never wake.
- **The way**: a session listed idle is a live process, so the line goes
  to its messaging socket, never a resume. A session not listed, or a
  background one done (its process exits after its turn), is resumed:
  `claude --resume ID --bg LINE` in its directory, with no other flag (a
  flag starts a copy under a new id; when one does, the wake says
  `copied NEW_ID` and the session's record moves to it).
- **The budget**: at most 2 wakes an hour and 8 a day per ledger. Only a
  pending entry wakes: a stalled piece never does.
- **Every wake** is a `wakes` row, per ledger named (time, path,
  outcome), listed under the switch on the ledger's page, and printed by
  the loop.
- **The format guard**: the line format and the Claude Code version it
  was established on are in `config/doorbell.json`, with the facts
  measured then. At start the waker compares `claude --version` with the
  recorded one and refuses to run when they differ, naming both.
  `bin/ledger-waker --probe` then establishes it again on a scratch
  session (interactive, under a tmux server of its own, a throwaway
  session id, settings of its own) in `~/.cache/ledger-waker-probe`, and
  rewrites the record when the line starts a turn there. `--once` makes
  one pass.

What the user sets up, once. `rake waker:install` does the first two
in `~/.claude/settings.json` (`SETTINGS=PATH` for another file):
merged in, every other key and hook kept, a hook already running the
same `ledger hook` word (as the skill's `ledger-hook.sh`) left alone,
the file backed up to `settings.json.bak-waker` with its mode kept, and
the probe's directory made; run twice, it changes nothing.
`rake waker:uninstall` takes out exactly what it added.

- **The hooks**, registered in their settings: `session-start` on
  SessionStart and `stamp` on Stop, each `command -v ledger >/dev/null
  2>&1 || exit 0; exec ledger hook NAME` like the skill's.
- **`crossSessionInbound: "accept"`** in their settings: a session in
  bypass mode otherwise holds a message from outside for approval.
- **The probe's directory trusted**: `cd ~/.cache/ledger-waker-probe &&
  claude`, answering "Yes, I trust this folder" (a directory under one
  already trusted is trusted too). The probe never answers that dialog:
  it refuses, naming the step.

## Files it creates and reads

Written:

- **The journal**, `~/.local/state/orchestration/journal.db` (mode 0600,
  in a directory made 0700, since it holds the viewer's password
  hashes), with SQLite's `-wal` and `-shm` beside it while it is in use;
  `LEDGER_JOURNAL` names another file (tests, a sandbox). `ledger new
  PATH --goal … --title … --short …` adds a ledger to it and refuses an
  address a live ledger holds; every other command writes rows of it. It
  holds each ledger's items, the events that changed them, the stall
  counter (`beat_line`, `beat_count`, `beat_session`, on the ledger's row,
  written by `check` without `--peek`, and only by the ledger's owning
  session), the viewer's inbox entries and takes, a
  mockup's files as blobs, and sesam's tables (users, invitations,
  passkeys), and the waker's tables (`sessions`, `session_ledgers`,
  `session_stops`, `wakes`). Nothing else is written: no file beside a
  ledger's address,
  nothing under a project's `.claude/`, so nothing of a ledger is
  git-tracked.
- **Closed ledgers** stay in the journal with `closed_at` set; the
  address is free again, and `new --carry` reads their noticed lines.

Read only:

- The `journal-write` and `heartbeat` hooks read no file, only the
  command and the output in the hook payload.
- `brief-constraints`, `brief-piece`, `finish`, `inbox`, `status-stop`, `one-list` and
  `session-start` open the
  journal read-only (a missing file means no ledgers, and the hook
  passes) and read the live ledgers whose address is directly under the
  session's directory, its `.claude/` or its scratch directory, and
  nowhere else: a ledger addressed in a subdirectory passes
  `bin/ledger`, but no hook sees it. `session-start` also shows the
  resume view (at most 10 000 characters across the session's ledgers:
  status line, Goal blocks, Constraints, open questions, open
  assumptions, pieces in
  flight), at a start, a resume and a compaction; any error is a silent
  exit 0, a start hook never blocks a session.
- The viewer reads the journal through `Ledger::Read`, and writes inbox
  entries, the waker's switch, sesam's tables (a sign-in, an
  invitation) and nothing else;
  its settings are `config/app.rb`, with local overrides in
  `~/.config/ledger-viewer/app.local.rb` (`config/app.local.rb.example`
  shows the form).

No hook writes a ledger: `session-start` writes `sessions` and
`session_ledgers`, `stamp` writes `session_stops`, both only when the
journal and those tables exist.

- `bin/ledger-waker` reads the journal, writes `wakes` and moves a
  session's record to a copy's id; `--probe` writes
  `config/doorbell.json` and the files of its scratch session under
  `~/.cache/ledger-waker-probe`, and reads `~/.claude.json` for that
  directory's trust alone.

## Tests

The gate is `bundle exec rake`: the minitest suite under `test/`, then
the house rubocop rules with this project's deltas in
`.rubocop.local.yml`; `rake test` and `rake rubocop` run either alone.

**The gate stamp.** When the default task passes, it writes the tree id
of the git index it tested (`git write-tree`, taken before the run and
compared after: an index that changed during the run is not stamped)
into `stamps/<repo id>` beside the journal, one tree per line, the last
50 kept (`rakelib/stamp.rake`, `lib/ledger/gate_stamp.rb`); the repo id
is the first 16 hex digits of the SHA-256 of the working tree's real
path. A project whose gate is not rake calls `ledger gate-stamp [PATH]
[--tree TREE]` at its end, `TREE` being what it took before the run.
`ledger githook install PATH` makes the stamps count: its pre-commit
hook passes a commit whose staged tree is stamped. Otherwise, from a
Claude session (`CLAUDECODE` set in the environment) it refuses the
commit with one sentence naming the gate; by hand it prints one warning
line and lets the commit through. The hook lives in `.git/ledger-hooks`
(core.hooksPath pointed there, the repository's other hooks linked into
it and its own pre-commit hook chained), or, when the repository's own
config already sets core.hooksPath, in that directory beside the
pre-commit hook it chains as `pre-commit.ledger-previous`; a path set in
global or system config is refused. `ledger githook uninstall PATH`
puts the previous state back; both are idempotent. Nothing installs a
hook by itself: the tests use scratch repositories only.

`rake gate:partial` is the edit loop's gate, over what changed since
`HEAD` and the untracked files (`BASE=ref` for another commit, or
`FILES="a b"` instead of the diff). It runs:

- **Tests**: each changed test, and the tests named after a changed
  file (`derive.rb` → `derive_test.rb`) or requiring it. A viewer file
  no test names (`lib/ledger_viewer/`, `views/`, `public/`) gets every
  test that loads `test_helper`, since those load the whole app.
- **Rubocop**: on the changed Ruby files, under the same rules.
- **A browser check**: when a page file changed, Chrome by default
  (`BROWSER=firefox|both|none`).

It names the changed `lib/ledger` files no test names rather than
passing them over. It is not the gate: a test can depend on a file
without naming it, so `rake` and both browser checks decide before a
commit.

```text
test/
├── test_helper.rb       a viewer over a sandbox: LEDGER_JOURNAL, the local
│                        config and the certificate directory all in a
│                        temporary directory; nothing reaches the real ones
├── ledger/              the engine, one directory per part of lib/ledger
│   ├── journal_test.rb, write_test.rb, lock_test.rb, claim_test.rb
│   │                    the journal, the write path (events, counters, a
│   │                    worse check rolling back), a second real writer
│   │                    refused after the timeout, the claim of a piece
│   ├── derive_test.rb   ready, stalled, awaiting, asked since, the
│   │                    status line as exact strings
│   ├── checks/          one failing case per rule of `check`
│   ├── commands/        each word of bin/ledger: output, refusals,
│   │                    --dry-run, the new id on the first line
│   ├── hooks/           each hook run on a payload: heartbeat,
│   │                    brief-constraints, journal-write, the Stop hooks,
│   │                    session-start and its resume view; every test
│   │                    checks the hook wrote no event; the session and
│   │                    stamp records of the waker
│   ├── waker_test.rb    the waker's pass with a fake socket and a stubbed
│   │                    claude: once, the budget, off, a stall, resume
│   ├── waker_main_test.rb  the version guard, the probe's trust refusal
│   ├── render/          show's Markdown per item kind, JSON v1
│   ├── text/            the title, picker, awaits, risk and option rules
│   ├── inbox_test.rb    entries, the take, --wait and --follow timing
│   ├── pictures_test.rb mockups as blobs, the types, the picking rule
│   └── read_test.rb     the JSON v1 reader and its refusal of an unknown
│                        schema
├── *_test.rb            the viewer (lib/ledger_viewer): the pages, the
│                        index, sends and their token, origin and sign-in
│                        checks, the inbox, the mockup route, the
│                        events stream, the links page, the waker's
│                        switch and wakes, configuration
├── browser/viewer.cjs   the page script and CSS in Chrome and Firefox:
│                        drafts kept, required choice, status fold, Close
│                        word, pane and window, quote, Cancel focus, a
│                        send collapsing into its Sent row and moving on to
│                        the next card, no reload of a ledger page, the
│                        paused-stream status, the tray of batch mode
└── browser_run.rb       runs the browser checks, below
```

`bundle exec ruby test/browser_run.rb` runs the browser checks against
the viewer in Chrome and Firefox: the fixture loaded into a sandbox
journal, the app on a free port over it, a user made and signed in. It
needs node and playwright-core and the browsers, and says what it skips
and exits 0 without them.

Every test points `LEDGER_JOURNAL` at a file in a temporary directory,
so none touches the real journal.

## Known shortfalls

- `check` checks shape, not truth: a paraphrased goal in quote marks
  passes.
- `journal-write` reads the words of a command; a script run from a
  file that writes the journal is beyond it.
- `ruby` on PATH from the Linux side is another build without the
  bundle's native sqlite3, so the launcher's last fallback fails there;
  `/usr/local/bin/ruby` or `$LEDGER_RUBY` is what the hooks use.
