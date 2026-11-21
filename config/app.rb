# -*- ruby -*-
# frozen_string_literal: true

# What is true of the program wherever it runs. Plain Ruby ending in a
# Hash; ~/.config/ledger-viewer/app.local.rb is read second and wins on
# any key. The ledgers and sesam's users are in the journal,
# $LEDGER_JOURNAL or ~/.local/state/orchestration/journal.db.

{
    # Where puma listens, and so the names the Host header may carry.
    bind: "tcp://127.0.0.1:4590",

    # Networks whose callers need no sign-in (each as 192.0.2.0/24 or
    # one address): none, so that everyone signs in. A caller there reads
    # the pages and sends answers; the form's token, Origin and same-site
    # checks still apply to it.
    lan: [],

    # Where rake tls leaves the certificate and key: outside the
    # checkout, which is pushed.
    tls_dir: "~/.config/ledger-viewer/tls",

    # How long a browser stays signed in, in days.
    session_days: 30
}
