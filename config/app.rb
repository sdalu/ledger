# -*- ruby -*-
# frozen_string_literal: true

# What is true of the program wherever it runs. Plain Ruby ending in a
# Hash; ~/.config/ledger-viewer/app.local.rb is read second and wins on
# any key.

{
    # Where puma listens, and so the names the Host header may carry.
    bind: "tcp://127.0.0.1:4590",

    # The engine, relative to this checkout. viewer.css is read from the
    # same directory.
    ledger_py: "../scripts/ledger.py",

    # The interpreter that runs it, and how long ledger-dump.py may take
    # to read one ledger before it is shown as unreadable, in seconds.
    python: "python3",
    dump_timeout: 10,

    # Networks whose callers need no sign-in (each as 192.0.2.0/24 or
    # one address): none, so that everyone signs in. A caller there reads
    # the pages and sends answers; the form's token, Origin and same-site
    # checks still apply to it.
    lan: [],

    # sesam's users, passkeys and invitations: one JSON file, made mode
    # 0600 at the first write, in a directory made mode 700 at start.
    # Outside the checkout, which is pushed.
    store: "~/.config/ledger-viewer/data/users.json",

    # Where rake tls leaves the certificate and key: outside the
    # checkout, which is pushed.
    tls_dir: "~/.config/ledger-viewer/tls",

    # How long a browser stays signed in, in days.
    session_days: 30
}
