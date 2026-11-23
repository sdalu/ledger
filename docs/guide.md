# A first read of ledger

This guide is for someone meeting `ledger` for the first time, a
person or a Claude session. It says what a ledger is and why it
exists, how a session, its hooks, the journal and the viewer fit
together, and then walks one small ledger from `ledger new` to
`ledger close`, each command with what it printed. It teaches the
flow and lists no flags: `README.md` is the reference for every word
and option, `docs/journal.md` the design.

## What a ledger is

A goal of many steps outlives the context of the session working on
it: the context is compacted, the session is resumed the next day,
the work is split across delegates. A ledger is where that goal is
held instead of in the session's memory, as rows of one SQLite file,
the journal, which every ledger of the machine shares. A session
reaches its ledger by an address, the path its file would have
(`.claude/LEDGER.md`), but nothing is ever written at that path: the
journal holds it.

A ledger is made of a few kinds of items, each with a letter and a
number that is never reused:

| Item       | Id     | What it holds                                         |
| ---------- | ------ | ----------------------------------------------------- |
| Goal       | `G<n>` | the user's words verbatim, a title and one sentence   |
| Done when  | `D<n>` | a criterion, marked met with evidence or not with why |
| Constraint | `C<n>` | the user's words verbatim, and where they were said   |
| Fact       | `F<n>` | something checked, and the pointer where it was found |
| Assumption | `A<n>` | something believed, and how it will be checked        |
| Decision   | `X<n>` | a choice, by the user or by the session (`by me`)     |
| Piece      | `P<n>` | a unit of work: its route, status and how it is done  |
| Open       | `O<n>` | a question to the user, with its case and options     |
| Noticed    | `Z<n>` | something seen and left out of scope                  |

Three rules make it something to trust rather than a notebook:

- **Every item has a writer.** A session changes its ledger only
  through `ledger WORD PATH`; no ledger is edited by hand, and a hook
  refuses a command that writes the journal file directly.
- **A write never makes the ledger worse.** Each write is one
  transaction that records an event, and is refused (exit 2, nothing
  written) when `check` on the result would fail a rule it passed
  before. `undo` and `restore` read those events.
- **The user's words are the user's.** The goal and the constraints
  are quoted, and `answer`, `word` and `decide --by user` are traced
  to the user's own messages in the session's transcript: a session
  cannot give itself the word it waits for.

## How the parts fit

```text
            ┌───────────────────┐  ledger WORD PATH  ┌─────────────────┐
  user ────►│ Claude session    ├───────────────────►│ journal         │
  (chat)    └─────────┬─────────┘                    │ one SQLite file │
                      │ tool calls, stops, starts    └──┬───────────┬──┘
                      ▼                                 │           │
            ┌───────────────────┐  reads                │           │
            │ ledger hook NAME  │◄──────────────────────┘           │
            └───────────────────┘                                   │
            ┌───────────────────┐  reads; writes the user's entries │
  user ────►│ ledger-viewer     │◄──────────────────────────────────┘
 (browser)  └───────────────────┘
```

- **The session** runs the orchestration skill and keeps its ledger
  with `ledger` commands, from the Bash tool. Each writer prints the
  line it wrote and the status line, so the session sees the effect
  of every write.
- **The hooks** are `ledger hook NAME`, run by Claude Code around the
  session's tool calls, stops and starts. They read the journal and
  never write a ledger. Some show things: the status line goes to the
  user after a `check`, and a session that starts, resumes or is
  compacted is shown the resume view of its ledgers. Others hold the
  session to its ledger: a stop is sent back once while the ledger
  fails `check --final` with nothing left to wait on, or while an
  entry from the viewer is pending; a task list is refused while a
  ledger is live; a `git commit`, `git merge` or `git push` in the
  main session is refused without the user's word on file.
- **The journal** is `~/.local/state/orchestration/journal.db`, or
  the file `LEDGER_JOURNAL` names (a test, a sandbox).
- **The viewer** is `bin/ledger-viewer`, a local web app the user
  starts. It shows every live ledger, with one queue of what waits on
  the user across all of them; the user answers questions and gives
  words there. What the user sends becomes an inbox entry (`N<n>`),
  which the session reads with `ledger inbox` and files with `answer`
  or `word` and `--take N<n>`.
- **The waker**, `bin/ledger-waker`, also started by the user, rings a
  session that sits idle while an entry of the user's waits on one of
  its ledgers, when that ledger's switch is on (`ledger waker PATH
  on`; off by default).

A ledger page in the viewer, top to bottom (a sketch, not a capture):

```text
┌──────────────────────────────────────────────────────────────┐
│ crumbs                                                       │
│ project                                                      │
│ The greet tool prints its version with --version, ...        │
│ ┌───────────────────────────────┐                            │
│ │ Answer O1: What --version ... │   Leave a note             │
│ └───────────────────────────────┘                            │
│ ▸ Details: waker off, batch off                              │
│ Waiting on you                                               │
│   O1 What --version prints        [ A ]  [ B, recommended ]  │
│ Goal, criteria not met, unfinished pieces, ...               │
└──────────────────────────────────────────────────────────────┘
```

## A piece's life

A piece is planned, goes out to whoever does it, comes back, and is
verified by the session; a piece that cannot move without the user
waits for a word.

```text
 ┌──────────────┐ word P<n>  ┌─────────┐ --status out  ┌─────┐
 │ planned,     ├───────────►│ planned ├──────────────►│ out │
 │ awaits start │ --word     │ (ready) │               └──┬──┘
 └──────────────┘ start      └────┬────┘                  │ --status back
                                  │                       │ --handback
                                  │ a return, from out    ▼
                                  │ or back: --status  ┌──────┐
                                  └─────────◄──────────┤ back │
                                   planned --cause C   └──┬───┘
                                                          │ --status verified
                                                          │ --verified-by WHO
                                                          ▼
                                                     ┌──────────┐
                                                     │ verified │
                                                     └──────────┘
```

- **Planned** is where a piece starts. It has a route, the model and
  effort that will do it (`sonnet, effort: low`), or `peer: SESSION`
  for another Claude session; or it is `kept: REASON`, done by the
  session itself.
- **A word awaited** (`--awaits start`, `commit`, `deploy`, `push`,
  `merge` or `other (what)`) keeps the piece from moving until the
  user gives it, and such a piece must state its problem and a risk
  rated out of ten. `ledger word` files the word as a decision by the
  user.
- **Out** claims the piece for the session that sent it; **back** is
  the hand-back, which the delegation skill's hook records; only the
  session moves it on to **verified**, naming who checked it. A piece
  sent back to planned names why (`--cause`), and `stats` counts the
  returns per route. Blocked, dropped, deferred and obsolete are
  reached by one flag each.

## A worked session

The session below makes a ledger for a small, invented goal: add a
`--version` flag to a tool named `greet` (the tool, its files, its
suite and its commit are made up). Every output was printed by
`ledger` on a scratch journal (`LEDGER_JOURNAL` pointing at a file in
a scratch directory), run outside a Claude session. So the commands
that trace the user's words warn `no transcript of this session
found` and check nothing (in a session, `answer` and `word` are
refused unless the user wrote after the item asked); `--status out`
was given `--session`, which a session's own id replaces; and the
address printed in full is shown as `/path/to/project/.claude/LEDGER.md`.

### Open the ledger

The goal goes in as the user said it, with a title and one sentence.

```bash
ledger new .claude/LEDGER.md \
  --goal "add a --version flag to the greet tool and document it" \
  --title "A --version flag for greet" \
  --short "The greet tool prints its version with --version, and the README says so."
```

```text
new: warning: no transcript of this session found (CLAUDE_CODE_SESSION_ID unset or its file absent); the quote is not checked
/path/to/project/.claude/LEDGER.md
```

`ledger show .claude/LEDGER.md` prints the ledger as Markdown. A new
one holds the goal and a placeholder criterion:

```text
# Ledger (format 2)

Goal G1 (2026-11-23, verbatim):
Title: A --version flag for greet
In short: The greet tool prints its version with --version, and the README says so.
> add a --version flag to the greet tool and document it

Done when:
- [ ] D1: <a check something other than opinion can pass> — evidence:
...
```

### Say what done means

The placeholder is replaced by a check something other than opinion
can pass.

```bash
ledger criterion .claude/LEDGER.md D1 \
  --text "greet --version prints the version from lib/greet/version.rb, and the README's Usage names the flag"
```

```text
- [ ] D1: greet --version prints the version from lib/greet/version.rb, and the README's Usage names the flag — evidence:
Status (A --version flag for greet) — criteria 0/1 · pieces 0/0 verified
```

The last line is the status line every writer ends with; its title
tells two live ledgers apart.

### Record a fact

A fact is something the session checked, and where. A command that
gives a new id prints it alone on its first line.

```bash
ledger fact .claude/LEDGER.md "greet parses its options with OptionParser — lib/greet/cli.rb:12"
```

```text
F1
- F1: greet parses its options with OptionParser — lib/greet/cli.rb:12
Status (A --version flag for greet) — criteria 0/1 · pieces 0/0 verified
```

### Plan a piece

```bash
ledger piece .claude/LEDGER.md new \
  --title "Add the --version option to the CLI" \
  --what "lib/greet/cli.rb gains --version, printing Greet::VERSION and exiting 0" \
  --done-when "greet --version prints the version; the suite passes" \
  --route "sonnet, effort: low" --for D1
```

```text
P1
- P1 [planned] sonnet, effort: low — Add the --version option to the CLI: lib/greet/cli.rb gains --version, printing Greet::VERSION and exiting 0 — done when: greet --version prints the version; the suite passes — for: D1
Status (A --version flag for greet) — criteria 0/1 · pieces 0/1 verified
```

### Ask the user, and file the answer

What the flag prints is the user's choice, so it becomes a question
with its case: the problem, a risk out of ten, the options with what
each does and costs, a recommendation, and whether it needs a
picture.

```bash
ledger ask .claude/LEDGER.md --title "What --version prints" \
  --problem "the flag's output is read by scripts and by people; the two want different forms" \
  --risk "2/10 — a script that parses the output breaks if it changes later" \
  --choices "A = the number alone, 1.4.0; easy to parse, says nothing to a person | B = greet 1.4.0; the GNU form, a script must split it" \
  --recommend "B, the form most tools print" \
  --no-picture "a one-line output, nothing to draw" \
  "What should greet --version print?"
```

```text
O1
- O1: What --version prints: What should greet --version print? — problem: the flag's output is read by scripts and by people; the two want different forms — risk: 2/10 — a script that parses the output breaks if it changes later — choices: A = the number alone, 1.4.0; easy to parse, says nothing to a person | B = greet 1.4.0; the GNU form, a script must split it — recommend: B, the form most tools print
Status (A --version flag for greet) — criteria 0/1 · pieces 0/1 verified · waiting on you: O1
```

The status line now says `waiting on you: O1`, and the viewer shows
the question with one button per option. The user answers there, or
in the chat; the session files the answer as a decision by the user:

```bash
ledger answer .claude/LEDGER.md O1 --decision "B: greet 1.4.0"
```

```text
answer: warning: no transcript of this session found (CLAUDE_CODE_SESSION_ID unset or its file absent); the word is not checked
X1
- 2026-11-23 — O1: B: greet 1.4.0 — by user
Status (A --version flag for greet) — criteria 0/1 · pieces 0/1 verified
```

The piece takes the answer in, and records the decision that led to
it:

```bash
ledger piece .claude/LEDGER.md P1 \
  --what "lib/greet/cli.rb gains --version, printing 'greet VERSION' and exiting 0" --by X1
```

### Send the piece, take it back, verify it

`--status out` claims the piece for the session (its
`CLAUDE_CODE_SESSION_ID`; here `--session` stood in for it):

```bash
ledger piece .claude/LEDGER.md P1 --status out
```

```text
- P1 [out] sonnet, effort: low — Add the --version option to the CLI: lib/greet/cli.rb gains --version, printing 'greet VERSION' and exiting 0 — done when: greet --version prints the version; the suite passes — for: D1
Status (A --version flag for greet) — criteria 0/1 · pieces 0/1 verified · out: P1
```

When the delegate hands back, the delegation skill's hook records it:

```bash
ledger piece .claude/LEDGER.md P1 --status back --handback
```

```text
hand-back recorded on .claude/LEDGER.md P1
```

The hand-back is not the finish: the session checks the work itself,
then marks the piece verified, saying who checked it and what showed
it.

```bash
ledger piece .claude/LEDGER.md P1 --status verified --verified-by me \
  --evidence "greet --version printed 'greet 1.4.0', exit 0; the suite passed, 41 runs"
```

```text
- P1 [verified] sonnet, effort: low — Add the --version option to the CLI: lib/greet/cli.rb gains --version, printing 'greet VERSION' and exiting 0 — done when: greet --version prints the version; the suite passes — for: D1 — evidence: greet --version printed 'greet 1.4.0', exit 0; the suite passed, 41 runs
Status (A --version flag for greet) — criteria 0/1 · pieces 1/1 verified
```

### A piece that awaits a word

The README line is small enough for the session to write itself, so
the second piece is kept, not routed; landing it needs the user's
commit word. Its first two tries were refused, exit 2, nothing
written, each naming what was missing:

```text
piece: --route (`sonnet, effort: medium[, skills: c]` or `peer: SESSION`) or --status 'kept: REASON'
piece: refused, pictures -- no before/after: P2 (awaits commit)
```

The third carries a status and a picture decision:

```bash
ledger piece .claude/LEDGER.md new --title "Document --version and commit" \
  --what "README.md's Usage names --version and its output; the CLI change and the README land in one commit" \
  --done-when "the commit is on main and git show names both files" \
  --status "kept: two lines of README, done in place" --for D1 --after P1 \
  --awaits commit \
  --problem "the flag exists only in the working tree until it is committed" \
  --risk "1/10 — a README line; a commit reverts alone" \
  --plan "stage lib/greet/cli.rb and README.md by path, commit them together" \
  --no-picture "a two-line README change, the diff shows it"
```

```text
P2
- P2 [kept: two lines of README, done in place] — Document --version and commit: README.md's Usage names --version and its output; the CLI change and the README land in one commit — problem: the flag exists only in the working tree until it is committed — risk: 1/10 — a README line; a commit reverts alone — plan: stage lib/greet/cli.rb and README.md by path, commit them together — done when: the commit is on main and git show names both files — after: P1 — for: D1 — awaits: commit
Status (A --version flag for greet) — criteria 0/1 · pieces 1/1 verified, 1 kept · your word: P2 (commit)
```

`your word: P2 (commit)` is what the user sees in the viewer's queue,
with the piece's problem, risk and plan. When the user gives it:

```bash
ledger word .claude/LEDGER.md P2 --word commit
```

```text
word: warning: no transcript of this session found (CLAUDE_CODE_SESSION_ID unset or its file absent); the word is not checked
X2
- 2026-11-23 — P2: "commit" — by user
- P2 [kept: two lines of README, done in place] — Document --version and commit: README.md's Usage names --version and its output; the CLI change and the README land in one commit — problem: the flag exists only in the working tree until it is committed — risk: 1/10 — a README line; a commit reverts alone — plan: stage lib/greet/cli.rb and README.md by path, commit them together — done when: the commit is on main and git show names both files — after: P1 — for: D1
Status (A --version flag for greet) — criteria 0/1 · pieces 1/1 verified, 1 kept
```

### Check, then check for the finish

`check` prints each rule's verdict, then the status line:

```bash
ledger check .claude/LEDGER.md
```

```text
ok   goal-titled
...
ok   assumptions-settled
Status (A --version flag for greet) — criteria 0/1 · pieces 1/1 verified, 1 kept
```

`check --final` adds the rules a finish must pass. Here it fails,
exit 1: the criterion is not marked, and the piece given its commit
word holds no commit yet.

```bash
ledger check --final .claude/LEDGER.md
```

```text
ok   goal-titled
...
ok   final-pieces
ok   final-deferred
ok   final-awaits
FAIL final-criteria -- D1 unmarked
warn final-commits -- P2 given its commit word, no commit
Status (A --version flag for greet) — criteria 0/1 · pieces 1/1 verified, 1 kept · unchanged ×1
```

`unchanged ×1` counts a status line that has not moved since the last
check. In a session the commit is attached by a hook after `git
commit`; here it was filed by hand, and the criterion marked met with
its evidence:

```bash
ledger piece .claude/LEDGER.md P2 --commits 3f2a9c1
ledger criterion .claude/LEDGER.md D1 \
  --met "greet --version printed 'greet 1.4.0' (P1); README.md Usage names the flag, commit 3f2a9c1 (P2)"
```

```text
- [x] D1: greet --version prints the version from lib/greet/version.rb, and the README's Usage names the flag — evidence: greet --version printed 'greet 1.4.0' (P1); README.md Usage names the flag, commit 3f2a9c1 (P2)
Status (A --version flag for greet) — criteria 1/1 · pieces 1/1 verified, 1 kept · done: propose close
```

`done: propose close` is the status line saying the session may offer
to close. `check --final` now prints `ok` on every rule and exits 0.

### Close

```bash
ledger close .claude/LEDGER.md
```

```text
after action:
answered: O1 0 min
closed: /path/to/project/.claude/LEDGER.md (L1)
```

The ledger's row stays in the journal, marked closed and out of every
hook's and the viewer's sight; `ledger show L1` still prints it.

## Where to go next

- `README.md`, the reference: every word, flag, refusal and hook, the
  viewer and the waker, the files and settings.
- `docs/journal.md`, the design: the schema, the write path, the
  derived states, the command contract, the check rules.
- `ledger help`, and `ledger help WORD` for one word's options.
