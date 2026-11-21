# frozen_string_literal: true

module Ledger
    module Checks
        # `check --fix-hints`: after each FAIL line, the form the rule
        # expects and the bin/ledger command that gives it, one per kept
        # rule.
        HINTS = {
            "goal-titled" =>
                "a Title is a phrase in words, at most 60 characters; " \
                "`bin/ledger edit PATH goal --text …`, or `bin/ledger goal " \
                "PATH --quote … --title … --short … [--context …]`",
            "goal-revision" =>
                "a revised Goal quotes at least 4 words; a go-ahead is a " \
                'Decision: `bin/ledger decide PATH "TEXT" --by user`',
            "criteria" =>
                "at least one criterion under Done when, a check something " \
                "other than opinion can pass; `bin/ledger criterion PATH " \
                "new --text …`",
            "open-choices" =>
                "an option holds no colon and is never drop or ignore; " \
                "per-item answers are `items: a | b` with `choices:`; " \
                "`bin/ledger choice PATH O<n> --drop LABEL`, or " \
                "`bin/ledger ask … --replaces O<n>` to redo it",
            "open-described" =>
                "a question gives `— problem:` and `— risk:`, and once it " \
                "can be answered `X = what it does` for each option and " \
                "`— recommend: X, why`; `bin/ledger ask PATH … --problem … " \
                '--risk … --choices "A = … | B = …" --recommend "A, why" ' \
                "--replaces O<n>`",
            "open-picker" =>
                "options are `label = effect; cost`, two to eight, no `?` " \
                "in an effect, at most one in the question, a recommend " \
                "`label, why`, no two questions with the same options; " \
                "`bin/ledger choice PATH O<n> --add …` or `--drop …`, or " \
                "`bin/ledger ask … --replaces O<n>` to split or redo it",
            "self-routed" =>
                "a piece is not routed to this ledger's own session; " \
                '`bin/ledger piece PATH P<n> --status "kept: REASON"` or ' \
                '`--route "sonnet, effort: medium"`',
            "links" =>
                "every link names a row of this ledger and `after` never " \
                "loops; `bin/ledger piece PATH P<n> --after P3,P5`",
            "pieces-awaits" =>
                "start only on a planned or kept piece, commit, deploy, " \
                "push and merge on a piece done; `bin/ledger piece PATH " \
                'P<n> --awaits "commit, deploy"`; a scope names only words ' \
                'the piece awaits: `--scope "commit = … | deploy = …"`',
            "titles" =>
                "a title is a phrase in words, at most 60 characters, " \
                "without \": \"; `bin/ledger piece PATH P<n> --title …`, a " \
                "question's by `bin/ledger ask … --replaces O<n>`",
            "details" =>
                "a detail says in words what ids stand for, or points to " \
                "them with `— see:`; `bin/ledger piece PATH P<n> --what …`, " \
                "a question's by `bin/ledger edit PATH O<n> --text …`",
            "codes" =>
                "say in words what a code that is not this ledger's " \
                "(W1, S4) stands for, instead of the code, or point a " \
                "question to where it is defined with `— see: F<n>`; " \
                "quoted user words and `code` are not read; `bin/ledger " \
                "piece PATH P<n> --what …`, `bin/ledger edit PATH F<n> " \
                "--text …`",
            "pieces-order" =>
                "a piece leaves planned only once what it waits for is " \
                "verified or kept, and waits for none dropped; " \
                "`bin/ledger piece PATH P<n> --status planned` or `--after …`",
            "criteria-pieces" =>
                "a criterion is met only once the pieces serving it are " \
                "finished; `bin/ledger piece PATH P<n> --status verified " \
                "--verified-by me --evidence …`, or `bin/ledger criterion " \
                "PATH D<n> --unmet WHY`",
            "case-rated" =>
                "a rated risk on every open question and on every piece " \
                "awaiting a word, a problem on that piece, Title and In " \
                "short on the latest Goal block; `bin/ledger piece PATH " \
                'P<n> --problem … --risk "N/10 — …"`, `bin/ledger ask … ' \
                "--replaces O<n>`, `bin/ledger goal PATH --quote … --title " \
                "… --short …`",
            "verified-by" =>
                "a piece is verified by someone other than its own route; " \
                "`bin/ledger piece PATH P<n> --status verified " \
                "--verified-by me`",
            "final-pieces" =>
                "no piece planned, out or back; `bin/ledger piece PATH P<n> " \
                "--status verified --verified-by me --evidence …` or " \
                "`--status dropped` with a Decision",
            "final-deferred" =>
                "no piece deferred: the ledger waits for its event; once " \
                "it came, `bin/ledger piece PATH P<n> --status planned`, " \
                "or `--status dropped` with a Decision",
            "final-awaits" =>
                "no piece waits for the user's word; `bin/ledger word PATH " \
                "P<n> --word W` once given, or `--word drop`",
            "final-criteria" =>
                "every criterion `[x]` with evidence or `[-]` with why; " \
                "`bin/ledger criterion PATH D<n> --met EVIDENCE` or " \
                "`--unmet WHY`"
        }.freeze
    end
end
