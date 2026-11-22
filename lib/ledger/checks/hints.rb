# frozen_string_literal: true

require "ledger/checks/assumptions"
require "ledger/checks/codes"
require "ledger/checks/criteria"
require "ledger/checks/final"
require "ledger/checks/fresh"
require "ledger/checks/goal"
require "ledger/checks/links"
require "ledger/checks/loops"
require "ledger/checks/open"
require "ledger/checks/option_pictures"
require "ledger/checks/pieces"
require "ledger/checks/sides"

module Ledger
    module Checks
        # `check --fix-hints`: after each FAIL line, the form the rule
        # expects and the bin/ledger command that gives it. Each module
        # that implements a rule keeps that rule's hint; this table keeps
        # those of the rules no single module owns, and the merge lists
        # the modules in runner order.
        HINTS = {
            "titles" =>
                "a title is a phrase in words, at most 60 characters, " \
                "without \": \"; `bin/ledger piece PATH P<n> --title …`, a " \
                "question's by `bin/ledger ask … --replaces O<n>`",
            "details" =>
                "a detail says in words what ids stand for, or points to " \
                "them with `— see:`; `bin/ledger piece PATH P<n> --what …`, " \
                "a question's by `bin/ledger edit PATH O<n> --text …`",
            "case-rated" =>
                "a rated risk on every open question and on every piece " \
                "awaiting a word, a problem on that piece, Title and In " \
                "short on the latest Goal block; `bin/ledger piece PATH " \
                'P<n> --problem … --risk "N/10 — …"`, `bin/ledger ask … ' \
                "--replaces O<n>`, `bin/ledger goal PATH --quote … --title " \
                "… --short …`"
        }.merge(*[Goal, Criteria, Open, Pieces, Links, Loops, Awaits, Sides,
                  Fresh, OptionPictures, Codes, Assumptions, Final]
                    .map { it::HINTS }).freeze
    end
end
