# frozen_string_literal: true

# The journal: one SQLite file holding every ledger, its history and
# the viewer's sign-in state. This file names the family of refusals;
# the parts (journal, snapshot, write path) are required below it.
module Ledger
    VERSION = "0.1.0"

    # The root of the family: callers rescue this and get every refusal
    # below as a sentence.
    class Error < StandardError; end

    # A write refused before anything was written (the command's exit 2).
    # Its rule names it in the outcomes a writer's refusal records: the
    # one given, else the class's own word (refused, unknown, claimed,
    # locked).
    class Refused < Error
        def initialize(message = nil, rule: nil)
            super(message)
            @rule = rule
        end

        def rule = @rule || self.class.name.split("::").last.downcase
    end

    # The write lock was not given within the busy timeout.
    class Locked < Refused
        def initialize(message = "journal is locked by another writer")
            super
        end
    end

    # An address, id or reference that names nothing in this journal.
    class Unknown < Refused; end

    # A piece out under another session (U12).
    class Claimed < Refused; end

    # The write would fail a check its before-state passed (step 6).
    class Worse < Refused; end
end

require "ledger/journal"
require "ledger/snapshot"
require "ledger/write"
