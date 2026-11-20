# -*- ruby -*-
# frozen_string_literal: true

# What is mounted where: the viewer, built once from config/app.rb and
# ~/.config/ledger-viewer/app.local.rb. Nothing here names the server:
# bin/ledger-viewer execs puma at this file, and any Rack server could run it.

$LOAD_PATH.unshift File.expand_path("lib", __dir__)

require "ledger_viewer"

run LedgerViewer::Web.configured(LedgerViewer::Config.load).new
