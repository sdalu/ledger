# ledger

The orchestration skill's ledger as a command: one SQLite journal, the
hooks that keep a session to it, and a local viewer.

## Where things are

- `README.md` -- how it works
- `docs/journal.md` -- why it is shaped so
- `HISTORY.md` -- what was tried
- `docs/guide.md` -- a first read
- `CHECKLIST.md` -- what closes a round

## Gate

Gate: `/opt/bin/low-priority bundle exec rake` (the suite, then rubocop),
and `bundle exec ruby test/browser_run.rb` with `ONLY=chrome` and with
`ONLY=firefox` when `lib/ledger_viewer/`, `views/` or `public/` changed.

Ruby style: the `ruby` skill (4-space indentation; its `rubocop.yml` is
the rule set, `Rakefile` layers `.rubocop.local.yml` on it).

## Traps

- **The real journal is never opened by a test or a trial**: the suite
  sandboxes `LEDGER_JOURNAL` (`test/test_helper.rb`), a migration is
  tried on a copy (`CHECKLIST.md`, Gates).
- **`rake` alone does not gate a viewer change, and `rake gate:partial`
  is not the gate**: the browser run is outside `rake`, the partial runs
  only tests naming the changed files (`CHECKLIST.md`, Gates).
- **A commit needs a stamp.** `rake` stamps the git index tree it tested
  (`stamp:begin`, `stamp:write`); in a Claude session the pre-commit
  check passes only a stamped staged tree, so changing the index after the gate
  voids it (`lib/ledger/gate_stamp.rb`, `rakelib/stamp.rake`).
- **Project relaxations never go in `.rubocop.yml`.** RuboCop would load
  it alone and drop the house rules (`.rubocop.local.yml`).
- **No private address or estate name in a tracked file**: they live in
  `config/app.local.rb` or the untracked `test/local.rb`
  (`test/tracked_files_test.rb`).
- **Hooks never write a ledger** (`README.md`, At a glance).
