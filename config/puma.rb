# frozen_string_literal: true

# How the viewer is served: one process, threads enough for the open
# event streams (one each) and the requests beside them, the
# addresses the local file names. Nothing under lib/ knows it.

require "fileutils"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "ledger_viewer"

settings = LedgerViewer::Config.load(root: File.expand_path("..", __dir__))

# So rake server:stop and server:restart find this process rather than
# guess at one from a command line. Relative to the checkout, which the
# launcher makes the working directory.
FileUtils.mkdir_p("tmp")
pidfile "tmp/puma.pid"

workers 0
threads 0, LedgerViewer::THREADS

settings.listeners.each { bind it }

# A request here is short: a restart waits for what is in flight, and no
# longer than this for one that hangs.
force_shutdown_after 30

before_restart { warn "ledger-viewer: restarting" }
