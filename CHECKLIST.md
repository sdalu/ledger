# Closing a round on ledger

What has to be true before a unit of work here is done.

## Gates

Run in order, from the checkout. A red gate is answered before anything
else.

- [ ] `/opt/bin/low-priority bundle exec rake` -- the suite, then
      rubocop; both must pass. `rake gate:partial` while editing is no
      substitute: it runs only the tests that name the changed files.
- [ ] `bundle exec ruby test/browser_run.rb`, once with `ONLY=chrome`
      and once with `ONLY=firefox` -- every line `ok`, whenever the
      round touched `lib/ledger_viewer/`, `views/` or `public/`. They
      are not part of `rake`, and a viewer change gated by `rake` alone
      has broken one.
- [ ] A round that adds a migration: open a copy of the real journal
      with the round's code (`LEDGER_JOURNAL=COPY`), never the journal
      itself, before main carries the migration.

## Documents

Re-read each against what this round changed.

- [ ] `README.md` -- does it still name only the words, flags and pages
      that exist, and does it say what this round changed?
- [ ] `docs/journal.md` -- does section 4 still match each command's
      output and refusals, and section 1 the schema after any migration?

This project names no release (no version file, no tag): nothing here
bumps.

## Each Claude Code release

The waker posts its doorbell on the session's messaging socket, whose
message format Claude Code does not document (decided 2026-11-21, after
the Channels docs showed a channel needs a launch flag on every session).

- [ ] Re-read https://code.claude.com/docs/en/channels.md and
      channels-reference.md: is a channel still a launch-flag opt-in per
      session, still a research preview? If a channel can now reach an
      idle session without a flag at each start, propose moving the
      waker to it.
- [ ] Does the waker's format probe still pass on the new version? A
      failed probe stops the waker; that is the signal to look here.
