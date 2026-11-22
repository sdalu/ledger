# History

What was tried in the ledger tool and did not hold, and the failures
that shaped what is there now. Each entry names the approach, why it
was dropped, and the commit (`git show SHA`) or measurement behind it;
what stands today is in [README.md](README.md) and
[docs/journal.md](docs/journal.md). An entry stays while the question
it closes can still be asked: an approach later adopted, or a
component since deleted, has none, and this is not a changelog.

## Journal

### Ledgers as files beside each project

- **Tried**: a ledger was a `LEDGER*.md` file in its project, written
  by Python scripts (a ledger tool and a server), the
  viewer reading them.
- **Dropped**: every ledger now lives in one SQLite journal per
  machine, written by `bin/ledger`, and no command writes a
  `LEDGER*.md` or a side file. The commit records the replacement and
  what went with it (the Python scripts, the shell checks, the parity
  tests against Python); it gives no reason beyond that.
- **Left behind**: a one-shot importer ran at the cutover and was not
  kept, and ten closed ledgers it could not place were refused whole.
  The file's name survives only as the form an address takes
  (docs/journal.md:751).
- **Evidence**: commit 70c126d.

### A picture's bytes stored inside its row

- **Tried**: the `bytes` column of `pictures`, one copy of the file per placement.
- **Dropped**: the same file placed again (a redraw, another ledger)
  stored its bytes again. `picture_blobs` keeps each distinct content
  once under its SHA-256 and a picture row points to it
  (`lib/ledger/migrations/019_picture_blobs.rb`).
- **Evidence**: commit b7da917, measured on a copy of the real journal
  (315 pictures, 290 distinct contents): 38.15 MB vacuumed before,
  35.57 MB vacuumed after. The commit message numbers the migration
  016; 341ba8c renumbered it behind the `said_in` one.

### A return to planned with no recorded reason

- **Tried**: a piece out or back that went back to planned (a retry)
  changed its status and nothing else.
- **Dropped**: the reason was lost, so nothing could count which
  briefs, cuts, tiers or environments made work come back. The return
  now needs `--cause` (`brief`, `split`, `depth`, `contract`, `env`)
  and writes a `piece_returns` row in the same event
  (`lib/ledger/migrations/002_piece_returns.rb`).
- **Evidence**: commit 2a47bc5.

### A track record read from every event

- **Tried**: `stats` counted the status changes it found in the
  journal, undone ones included, and kept a group for pieces with no
  route.
- **Dropped**: an undone claim read as a return to planned, and an
  undone return lost its `piece_returns` row but kept its status
  change, so the record counted work the ledger had taken back. Only
  events still in force count (`lib/ledger/stats/in_force.rb`). The
  schema forbids a piece with neither route nor `kept`, so the group
  for it was code that could not run, and it went.
- **Evidence**: commit f2e0c8a.

### A dropped piece holding back what waits on it

- **Tried**: `ready` treated a dropped `after` piece as unfinished, so
  a piece waiting on it stayed planned.
- **Dropped**: a dropped piece settles like a verified or kept one
  (docs/journal.md:872). The same change made a ready piece left
  planned past a limit visible as unsent, since nothing said it had
  never been sent out.
- **Evidence**: commit 9916e4a.

## Hooks

### Every hook through the bundle

- **Rejected**: starting every hook under `-r bundler/setup` with
  Sequel loaded, as the other words start.
- **Why**: the heartbeat runs after every Bash call. Measured
  2026-11-20 on `/usr/local/bin/ruby`: a bare start 0.03 to 0.06 s,
  `-rbundler/setup` 0.11 to 0.19 s, Sequel loaded and a database
  opened 0.20 s. The hooks that read no journal start with `-I lib`
  alone (`bin/ledger:57-60`), and `stamp` writes its row through the
  `sqlite3` program (`lib/ledger/hooks/stamp.rb:11`).
- **Evidence**: the measurement in docs/journal.md (section 7), added
  by commit 70c126d; commit cca2296 for `stamp`.

### A launcher that names only its Gemfile

- **Tried**: `BUNDLE_GEMFILE` alone to point a launch at this checkout.
- **Dropped**: a `BUNDLE_LOCKFILE` inherited from another project's
  bundle beats the lockfile Bundler derives from `BUNDLE_GEMFILE`
  (bundler 4.0.21, its shared helpers, lines 25-27), so the launch rewrote
  the other project's lockfile with this checkout's gems. `bin/ledger`
  now exports the Gemfile, the lockfile and `BUNDLE_FROZEN=true`
  before every path (`bin/ledger:35-38`); a lockfile that does not
  match stops the command instead of being rewritten.
- **Evidence**: commit c713d66.

### A stop sent back for criteria that cannot be marked yet

- **Tried**: the `finish` hook sent the stop back whenever
  `check --final` failed.
- **Dropped**: a ledger whose only work left is a deferred piece failed
  `final-criteria` beside `final-deferred`, though those criteria can
  only be marked once the deferred event comes. The hook now lets the
  stop through when exactly those two rules fail and every unmarked
  criterion waits on deferred pieces or on none
  (`lib/ledger/hooks/finish.rb:20-24`); `check --final` itself still
  fails.
- **Evidence**: commit 0bcce44.

## Viewer

### Every piece a full card

- **Tried**: each planned or deferred piece drawn as a card in the
  first screen.
- **Dropped**: the first screen has to show the work. A planned or
  deferred piece with nothing to say (no problem, risk, plan, awaited
  word or picture) is now one row that opens into the card
  (`views/ledger/flight_row.erb`); out, back and blocked pieces stay
  cards.
- **Evidence**: commit ccf809d, whose browser check holds the first
  question's title above the fold at 390x844.

### A card send that posts itself again

- **Tried**: a send that got no answer (network error, no redirect,
  5xx) re-posted the form by itself.
- **Dropped**: the server refuses a send that had landed, so the retry
  turned a delivered answer into an error. The card keeps its draft and
  says *Delivery unconfirmed* with a Check button that reads the card;
  a landed send is drawn as sent, otherwise the button becomes Retry
  and posts once (`public/viewer.js:1043`).
- **Evidence**: commit 5272bb0.

### Browser checks sharing fixtures and fixed waits

- **Tried**: the checks named their second ledgers and one question's
  options the same for each browser, and the group chip's check waited
  a fixed 300 ms for its tip.
- **Dropped**: the second browser's run was refused on the shared
  address and options, so every check after it went unrun; the names
  now carry the browser (`test/browser/viewer.cjs`, commit e8d60a8).
  Firefox showed the tip after the 300 ms at times, so the check waits
  for the tip, up to 3 s (`test/browser/groups.cjs:46`, commit
  a677e51).
- **Evidence**: the two commits.

## Waker

### A resume that carries the session's flags

- **Tried**: waking an exited session with `claude --resume ID --bg`
  and further flags.
- **Dropped**: with any other flag Claude Code 2.1.329 starts a copy
  under a new id; with none it continues the session under its id. The
  waker passes none, and a copy that starts anyway is recorded
  `copied ID`. The line format and the three facts it rests on are
  kept in `config/doorbell.json` (fact c), and the waker refuses to
  start on another Claude Code version.
- **Evidence**: commit cca2296 (the facts were measured on scratch
  sessions on 2026-11-21).

## CLI and rake

### `rake server` and `rake status`

- **Tried**: short aliases for `server:start` and `server:status`.
- **Dropped**: the tasks are named in full everywhere, and the aliases
  now fail with "Don't know how to build task"
  (`rakelib/server.rake:149`, the `server` namespace only).
- **Evidence**: commit 2b6370b.

### A detached start from bundler's own copy of the environment

- **Tried**: `server:start TMUX=` or `SCREEN=` began from
  `Bundler.unbundled_env`.
- **Dropped**: bundler takes that copy when it loads, and rake sets
  `VAR=value` arguments after that, so `DEBUG=1 TMUX=x` detached
  without `DEBUG=1`. The start now merges back what was set since,
  less bundler's own variables (`rakelib/server.rake:112-123`).
- **Evidence**: commit c713d66; `test/detached_env_test.rb` pins both
  halves and failed on the old task for that reason.
