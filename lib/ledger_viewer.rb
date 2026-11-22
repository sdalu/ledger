# frozen_string_literal: true

# The ledger viewer: the live ledgers of the journal, served behind
# sesam's sign-in, each page read through Ledger::Read.
module LedgerViewer
    VERSION = "0.1.0"

    # The request threads of the server: each open event stream holds
    # a thread for as long as its page is open.
    THREADS = 16

    # The root of the family: callers rescue this and get every refusal
    # below as a sentence.
    class Error < StandardError; end

    # A setting that cannot be used, said with its key.
    class ConfigError < Error; end

    # DEBUG=1 and PRODUCTION=1 together.
    class ModeError < Error; end

    # Editing: the real exception page and request logging.
    def self.debug? = ENV["DEBUG"] == "1"

    # Refused here, where every entry point loads it, not in the
    # launcher alone: `puma config.ru` obeys the same rule.
    def self.check_mode!
        return unless debug? && ENV["PRODUCTION"] == "1"

        raise ModeError, "DEBUG=1 and PRODUCTION=1 contradict each other"
    end
end

LedgerViewer.check_mode!

require "ledger_viewer/config"
require "ledger_viewer/events"
require "ledger_viewer/form"
require "ledger_viewer/form_token"
require "ledger_viewer/headers"
require "ledger_viewer/lan"
require "ledger_viewer/ledgers"
require "ledger_viewer/mockup_files"
require "ledger_viewer/mockup_token"
require "ledger_viewer/render"
require "ledger_viewer/sender"
require "ledger_viewer/sends"
require "ledger_viewer/waker_switch"
require "ledger_viewer/accounts"
require "ledger_viewer/web"
