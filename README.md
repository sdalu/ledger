# ledger

The orchestration skill's ledger as a command: one SQLite journal that
holds every ledger of the machine and its history, the hooks that keep a
session to it, and a local viewer where the user answers.

## At a glance

A session writes its ledger only through `bin/ledger`; the hooks read
the journal and never write it; the viewer writes the user's entries
and nothing else. `docs/journal.md` is the design note: the schema, the
write path, the derived states, the command contract, the check rules,
the hooks.

```text
 ┌───────────────────┐  ledger WORD PATH  ┌────────────────────────────┐
 │ session           ├───────────────────▸│ journal (SQLite, Sequel)   │
 └─────────┬─────────┘                    │ ledgers, items, events,    │
           │ Bash, Agent, Stop,           │ inbox entries, pictures,   │
           │ SessionStart                 │ sesam's sign-in tables     │
           ▼                              └──────┬───────────────┬─────┘
 ┌───────────────────┐  reads, never writes      │               │
 │ ledger hook NAME  │◂──────────────────────────┘               │
 └───────────────────┘                                           │
 ┌───────────────────┐  reads; writes inbox entries alone        │
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
value` per line, an unknown id exiting 2. `stats [PATH]` prints a track
record per route (model and effort, each peer, kept) over every ledger,
live and closed, or one (`L<id>` reaches a closed one): pieces, the
share verified without a return, the share ever blocked, the median
time out, the returns by cause, and over every ledger a last line
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
`--cause`, `--no-picture WHY`; an empty value clears a link); a piece not done that
waits on an event to come, not on the user, is `--status deferred
--until CONDITION`, the event kept on its line (`— until: three
closures`) and in the viewer's remains until another status clears
it; `ask PATH --title TITLE "question"
[--choices "A = … | B = …"] [--recommend "A, why"] [--items "x | y"]
[--by P<n>] [--see F2] (--mockup NAME | --pending P<n> | --no-picture
WHY) [--replaces O<n>]` puts a question under Open (it refuses one
without a picture decision or breaking the picker grammar,
`check`'s `open-picker`; `--replaces` closes O<n> in the same write, a
Decision `by me`; `--dry-run` also prints the card's picker); `answer
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
a fact (its pointer with `--pointer`), constraint, decision, question detail or noticed line (`Z<n>`),
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
starts the new ledger with them.

An id is never reused: the counters live beside the events, so an
answered, dropped or undone item does not give its id back. Each writer
runs as one `BEGIN IMMEDIATE` transaction that records an event with
every row's before and after, and writes only when `check` on the result
fails nothing it passed before and names no failure on the item written;
it prints the line and the status line. A second writer waits for the
lock and gives up with exit 2 after 10 seconds. `--dry-run` on every
writer but `new`, `take`, `close` and `mockup` prints a unified diff of
the `show` text and the status line the change would give and writes
nothing (exit 2 with the refusal when it would refuse).

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
status stays out, and no return is recorded. `undo PATH` puts back the last event that changed the
ledger's items, in an event of its own, one level, refused once a row
changed since; the inbox's takes are never undone. `restore PATH --to
E<n>` puts back every item-changing event after `E<n>`; without `--to`
it lists the last ten events and refuses. The `self-routed` check fails
a piece in flight, awaiting no word, routed `peer:` to the ledger's own
project (the session that holds the ledger): keep it or route it to a
delegate.

## The hooks

Six words of `ledger hook NAME`, each reading the payload on stdin,
writing nothing, and turning any error of its own into exit 0. The
orchestration skill registers five in its front matter and
`session-start` in its `hooks.json`.

- **heartbeat** (PostToolUse, Bash): when the command it ran names
  `ledger … check` or `ledger … status`, the last `Status —` line it
  finds in the output goes to the user as a `systemMessage`. `check`
  also counts repeats: a line that has not changed since the last check
  is marked `unchanged ×N`. The count is kept on the ledger's row, not
  as an event, so an undo does not move it; `check --peek` reads without
  counting. A piece `out` with no event on it for 60 minutes
  (`LEDGER_STALL_MINUTES` changes the budget) is named `stalled:`.
- **brief-constraints** (PreToolUse, Agent): reads the Constraints of
  the session's ledgers, and a brief that names a path one of them names
  (`vendor/`, `units/time.py`) without carrying it verbatim is refused.
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
  goes through. The retry is let through
  whatever it did.
- **inbox** (Stop): pending viewer entries refuse the stop once,
  verbatim, with the filing steps.
- **session-start** (SessionStart): the entries waiting at the start,
  and on a start, resume or compaction the resume view of the session's
  ledgers.

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
Then the sessions' turn (answers sent and awaiting filing, questions
being prepared) and a table of the ledgers, each with its state in
words (the words still owed, counted, then how many are sent; an
`other` word's need on a line under its row), its changed time under
its name, narrow enough for a phone. A ledger page has the questions as
a list beside it when the page is wide enough for both (to answer,
sent, being prepared, then the other sections), above it otherwise;
each option of a question is a tile with what it does and costs, and
each card after Send offers the next question. The note box sits under
the Goal, folded; "Leave a note" opens it. The Goal section shows every
block not done, newest first, each headed by its `G<n>` chip, with its
title, its short line and its context, the user's own words folded under
them (open when the block has neither title nor short); the done blocks
are folded under *Done goals · N*, newest first, each with its
evidence. On top of the page,
the next step ("Answer O1: …", "Leave a note"), the path and the
session's status line folded under *Ledger details*, then what remains
(questions to answer, answers sent and awaiting filing, questions being
prepared, unfinished pieces with a fold to propose their order,
criteria not met, failing shape checks) with what is done folded below.
Every piece card (in flight, waiting on a word, on record) and every
question card carries a RAID line under its case, each part left out
when it has nothing to say: the risk (its ten-step meter, or *no risk
rated* for a piece in flight), the assumptions it rests on (`rests on
A1 (open), A2 (refuted)`, each chip leading to its row), its issues
(`blocked`, `stalled 2 h`, `returned 2: depth, unrecorded`) and what it
depends on (`waits for P3`, `serves D2`, `answered by P5`, `see F2`).
The record opens with a *RAID* fold of four lists: Risks (every rated
one, highest first), Assumptions (open first, then confirmed and
refuted, each with its check, what it rests on, what rests on it and the
fact that settled it; then the decisions by me, the session's
reviewable judgements, each with what it rests on), Issues (open
questions, blocked and stalled pieces, failing
checks, noticed lines) and Dependencies (each after or by piece not
settled, each deferred condition). A stalled piece says so in the side
list too (`out · stalled 2 h · with sonnet`).
A question already answered counts as the session's turn, not the
user's. Every request reads the journal, and the index reloads itself
within three seconds of a ledger changing, unless a form differs from
what the server sent, a box is being typed in, or a mockup is open. A
ledger page never reloads by itself: a note says *Ledger changed* with
a *Refresh* button, which reloads and returns to the same scroll
position and open folds, and puts back what was picked or typed in an
answer form and not sent (kept in `sessionStorage` per ledger and item,
a line on the card saying so; a choice no longer offered is said,
nothing sent). When the live stream has been down for 10 seconds, a
quiet *Live updates paused* status shows in the page head until it
returns; the 3 s poll runs meanwhile. The user starts it; no hook does.

A ledger page reads, top to bottom and in the tab order: crumbs, the
title, the next step (the id, then `Your word: TITLE`, the words as
icons and in text), the tiles (Waiting on you, then Criteria, which links
the met-criteria fold once all are met, and Work verified; Unfinished
pieces only when some are; they share each row), Waiting on you, the side
list folded as *Sections of this ledger*,
then the Goal with the user's words folded. With room (64 rem) the side
list stands beside, Waiting still above the Goal, and both folds are
open; the page script keeps each fold's own state for a narrow page. A
*Skip to waiting work* link comes first and shows on focus. A
criterion's serving pieces are counted (`16 pieces: 15 verified, 1
kept`), their links folded; the section of what was sent is *Sent,
awaiting filing*, the filed ones *Filed (N)*.

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
  starts only once it can be answered.
- **A comment on a question**, not an answer (to ask for more before
  answering): below an open question's answer form, a fold *Ask about
  O<n>* with its own *Send question*; the entry carries `comment: true`
  and the text, and the server refuses it empty or once the question is
  no longer open. It replaces nothing, and an answer sent after it need
  not name it; the card stays a question to answer, with *asked: N<n>,
  sent HH:MM · awaiting filing* until the session takes it, and only
  that line and the fold are redrawn when it is sent with `fetch`.
  `ledger inbox` shows it as *comment on question O<n>, not an answer*.
- **A comment on a planned piece**, before it goes out, and with two or
  more planned, **a proposed order**, refused unless it names each
  planned piece once.
- **A word on a piece** the ledger says awaits one (`— awaits: start`,
  on a planned or kept piece; `commit, deploy`, `other (what)`; the
  words are start, commit, deploy, push, merge): its card under Waiting
  on you reads problem first (head, problem and plan, its RAID line,
  then *What it covers* folded) and has
  a button per word, the one for all of them filled and first (no click
  is the wait); the entry carries `word`, and the server refuses a word
  the piece does not await. A piece may carry `— scope: commit = what it
  authorises | deploy = …` (`piece --scope`, only for words it awaits,
  pruned as words are given), shown under each word's button. The
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
  without transition, smooth scroll or pulse. A refusal, a failed fetch
  or a card that did not become a receipt falls back to the plain form
  post. Without script the send answers 303 to the next card waiting
  (`#p-P<n>`, `#q-O<n>`), to the answered card when none waits; a
  comment, a note or an order goes back to its own card or `#inbox`. A
  piece whose word is sent shows a receipt, *You asked: Commit + Deploy
  · sent HH:MM · awaiting filing*, then a link to the next card waiting
  or *Nothing else waits on you*. When two or more pieces wait and all
  await the same words (none `other`), a bar under the Waiting heading
  gives them all in one request (`POST /l/ID/say-all`: token, Origin and
  Host as `/say`; refused with 409, sending nothing, if any no longer
  awaits exactly those words): one word entry per piece. Any piece in
  flight can also be dropped, as a request: a trash icon (a 44 px
  target) in its title opens a fold *Ask the session to close P<n>
  without follow-up*, what it does, an optional reason, *Cancel* (back
  to the trash) and *Ask to close P<n>*, the one red button, sending the
  word `drop`. Questions have the same icon, to drop (ignore) one; so a
  question never offers drop or ignore among its choices (`check` fails
  it, save per item).
- **The close of the ledger**, only while its status line ends with
  `done: propose close`: the head reads *Ready to close.* and offers
  *Close the ledger*, a fold that says what closing does, takes an
  optional comment, and sends only with *Yes, close it* (*Cancel* folds
  it back). The entry has `ref` `close`; the server refuses it, 409,
  once the status no longer proposes the close, which it stops doing
  as soon as any entry waits, the Close sent before among them. Sent,
  the head shows *close asked* with its receipt until a session files
  it with `ledger close PATH --take N<n>`, closing the ledger and
  taking the entry in one event; a close refused takes nothing.
- **The abandon of the ledger**, on any live ledger, after the Close
  when the Close is offered: *Abandon the ledger*, a fold that says what
  abandoning does (the pieces not finished dropped, the open questions
  closed, the history kept), takes an optional comment, and sends only
  with *Yes, abandon it*, the red button. The entry has `ref` `abandon`;
  the server refuses a second, 409, while one waits to be filed. Sent,
  the head shows *abandon asked* with its receipt until a session files
  it with `ledger close PATH --abandon --take N<n>`.
- **A note** per ledger.

Every box has a *Quote last selection* button, enabled once text on
the page has been selected: it goes in as a `>` quote, a blank line
after it, so several quotes and comments leave as one entry; the
button sits under the box it fills, in a row of its own, so Send stands
alone. A question's choice is required: Send is refused with none
picked, and a choice whose text says `in your comment` opens its
comment on being picked, says what to write there and requires it. A
card's status is one pill that opens, on a tap, to what the status
means after the word, in the same pill; an
item id is drawn in two halves (the letter pale, the number on the
chip's own colour, in gray when it has none) so the letter O differs
from the digit 0 in any
font; the trash says *Close* beside its icon where the card is narrow.
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
places one. The files are read into the journal as `pictures` rows (the
bytes as they are, with the content type the viewer serves), whatever
directory or worktree the command runs in, so a peer drawing in a
worktree lands it in the ledger it names; nothing is written on disk. A
FILE is stored by its name, a DIR as one name with a row per file, its
CSS and images under it. Before anything is stored it refuses a kind the
viewer would not serve (`Ledger::Pictures::TYPES`), a symlink, a name
`mockup: NAME` cannot spell, a name the ledger already placed, a missing
or unknown question, and an ambiguous pick. On the question,
`mockup: pending (P<n>)` on the question becomes `mockup: NAME` (the
page placed, or the image, or `--name`), else ` — mockup: NAME` is
added. With `--replace` every picture of the question gives way to the
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
and nothing else. Its pages run in an
opaque origin, by a `sandbox` CSP that holds even when one is opened
on its own, with no fetch, no form and no frame, so a mockup can
neither read the viewer's token nor post to it.

A piece awaiting commit, deploy, push or merge shows what the word
changes: `bin/ledger mockup PATH FILE --piece P<n> --before` (or
`--after`) places one file as that side, and its card under Waiting on
you draws the pair as one tile, *Before* on the left and *After* on the
right, each opening full size; a side already placed is refused unless
`--replace` takes it away (its blob stays). A piece with nothing to
show says why with `bin/ledger piece PATH P<n> --no-picture WHY`, drawn
on its card as a muted line `no picture: WHY`. `check`'s `pictures` rule
fails such a piece with neither both sides nor a reason, so the write
that makes it await the word is refused until one is given; `start` and
`other (…)` ask for none. `undo` takes a placed side back.

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
page reloads, or notes that the ledger changed when a draft is open,
within about a second of a ledger write. The 3 s poll of `/stamp`
remains as the fallback, slowed to 30 s while the stream is open. A sent
card reads `sent HH:MM · unfiled for N min`, a filed entry reads `filed
at HH:MM` (the take event's time), and the header reads `Ledger updated
today HH:MM` (the ISO date instead of `today` when it is not). Times
are local, 24-hour.

```text
 bin/ledger-viewer
 rake user:invite NAME=alice
```

## Files it creates and reads

Written:

- **The journal**, `~/.local/state/orchestration/journal.db` (mode 0600,
  in a directory made 0700, since it holds the viewer's password
  hashes), with SQLite's `-wal` and `-shm` beside it while it is in use;
  `LEDGER_JOURNAL` names another file (tests, a sandbox). `ledger new
  PATH --goal … --title … --short …` adds a ledger to it and refuses an
  address a live ledger holds; every other command writes rows of it. It
  holds each ledger's items, the events that changed them, the stall
  counter (`beat_line`, `beat_count`, on the ledger's row, written by
  `check` without `--peek`), the viewer's inbox entries and takes, a
  mockup's files as blobs, and sesam's tables (users, invitations,
  passkeys). Nothing else is written: no file beside a ledger's address,
  nothing under a project's `.claude/`, so nothing of a ledger is
  git-tracked.
- **Closed ledgers** stay in the journal with `closed_at` set; the
  address is free again, and `new --carry` reads their noticed lines.

Read only:

- The `journal-write` and `heartbeat` hooks read no file, only the
  command and the output in the hook payload.
- `brief-constraints`, `finish`, `inbox` and `session-start` open the
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
  entries, sesam's tables (a sign-in, an invitation) and nothing else;
  its settings are `config/app.rb`, with local overrides in
  `~/.config/ledger-viewer/app.local.rb` (`config/app.local.rb.example`
  shows the form).

No hook writes anything.

## Tests

The gate is `bundle exec rake`: the minitest suite under `test/`, then
the house rubocop rules with this project's deltas in
`.rubocop.local.yml`; `rake test` and `rake rubocop` run either alone.

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
│   │                    checks the hook wrote nothing
│   ├── render/          show's Markdown per item kind, JSON v1
│   ├── text/            the title, picker, awaits, risk and option rules
│   ├── inbox_test.rb    entries, the take, --wait and --follow timing
│   ├── pictures_test.rb mockups as blobs, the types, the picking rule
│   └── read_test.rb     the JSON v1 reader and its refusal of an unknown
│                        schema
├── *_test.rb            the viewer (lib/ledger_viewer): the pages, the
│                        index, sends and their token, origin and sign-in
│                        checks, the inbox, the mockup route, the
│                        events stream, the links page, configuration
├── browser/viewer.cjs   the page script and CSS in Chrome and Firefox:
│                        drafts kept, required choice, status fold, Close
│                        word, pane and window, quote, Cancel focus, a
│                        send collapsing into its Sent row and moving on to
│                        the next card, no reload of a ledger page, the
│                        paused-stream status
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
