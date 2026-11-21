# -*- ruby -*-
# frozen_string_literal: true

# The viewer as test/browser_run.rb serves it: config.ru's app. The
# browser checks change the ledger through bin/ledger, against the
# journal in $LEDGER_JOURNAL.

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "ledger_viewer"

run LedgerViewer::Web.configured(LedgerViewer::Config.load).new
