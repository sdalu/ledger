# frozen_string_literal: true

require "ledger/checks/assumptions"
require "ledger/checks/codes"
require "ledger/checks/criteria"
require "ledger/checks/final"
require "ledger/checks/fresh"
require "ledger/checks/goal"
require "ledger/checks/hints"
require "ledger/checks/links"
require "ledger/checks/open"
require "ledger/checks/option_pictures"
require "ledger/checks/pieces"
require "ledger/checks/sides"

module Ledger
    # The check rules of `ledger check` (docs/journal.md, section 5), in
    # the order they are printed, `case-rated` and
    # the new `verified-by` after them, the `--final` rules last. Each
    # rule answers its problems for a Derive of the snapshot; a rule
    # passes when it has none. A warning rule's problems fail `--final`
    # only: a plain check passes it with them as its detail, and so with
    # the notes it announces; the write path compares the problems its
    # module answers for that (`compared`).
    #
    #     Ledger::Checks.run(snapshot, final: true)
    #     # => [["goal-titled", true, ""], ["criteria", false, "need …"]]
    #     Ledger::Write.run(journal, address, cmd, argv,
    #                       checks: Ledger::Checks) { … }
    module Checks
        # PREFIX opens the detail of a failure, JOIN joins its problems;
        # WARN is a warning rule's module (problems, final, notes,
        # compared).
        Rule = Data.define(:name, :rule, :prefix, :join, :final, :warn) do
            def detail(problems) = "#{prefix}#{problems.join(join)}"

            # The problems a run reports; a warning rule's --final ones
            # are its own.
            def problems(derive, final)
                warn && final ? warn.final(derive) : rule.call(derive)
            end

            # What a warning rule announces; [] for any other.
            def notes(derive) = warn ? warn.notes(derive) : []

            # The problems the write path compares.
            def compared(derive)
                warn ? warn.compared(derive) : rule.call(derive)
            end
        end

        def self.rule(name, rule, prefix: "", join: "; ", final: false)
            Rule.new(name:, rule:, prefix:, join:, final:, warn: nil)
        end

        # A rule that warns on a plain check and fails `--final`.
        def self.warning(name, kind)
            Rule.new(name:, rule: kind.method(:problems), prefix: "",
                     join: "; ", final: false, warn: kind)
        end

        RULES = [
            rule("goal-titled", Goal.method(:titled), prefix: Goal::TITLED),
            rule("goal-revision", Goal.method(:revision),
                 prefix: "#{Goal::GO_AHEAD}: "),
            rule("criteria", Criteria.method(:present)),
            rule("open-choices", Open.method(:choices)),
            rule("open-described", Open.method(:described)),
            rule("open-picker", Open.method(:picker)),
            rule("self-routed", Pieces.method(:self_routed)),
            rule("links", Links.method(:problems)),
            rule("pieces-awaits", Awaits.method(:problems)),
            rule("pictures", Sides.method(:problems),
                 prefix: "no before/after: "),
            warning("pictures-fresh", Fresh),
            warning("pictures-options", OptionPictures),
            rule("titles", ->(d) { Pieces.titles(d) + Open.titles(d) }),
            rule("details", ->(d) { Pieces.details(d) + Open.details(d) }),
            rule("codes", Codes.method(:problems)),
            rule("pieces-order", Pieces.method(:order)),
            rule("criteria-pieces", Criteria.method(:pieces)),
            rule("case-rated", lambda do |d|
                Open.rated(d) + Pieces.rated(d) + Goal.rated(d)
            end),
            rule("verified-by", Pieces.method(:verified_by)),
            rule("assumptions-refuted", Assumptions.method(:refuted)),
            rule("assumptions-settled", Assumptions.method(:settled)),
            rule("final-pieces", Final.method(:pieces),
                 prefix: "still open: ", join: ", ", final: true),
            rule("final-deferred", Final.method(:deferred),
                 prefix: "deferred: ", join: ", ", final: true),
            rule("final-awaits", Final.method(:awaits),
                 prefix: "the user's word still owed: ", final: true),
            rule("final-criteria", Final.method(:criteria), final: true)
        ].freeze

        # The rules that answer [item, token] pairs: the write path
        # refuses a write for them only by the pairs it adds.
        FINDINGS = { "codes" => Codes.method(:findings) }.freeze
        # The rules the write path never compares: the write they would
        # refuse is the one that records what was found (`assume A<n>
        # --refuted-by F<n>`).
        REPORTED = %w[assumptions-refuted].freeze

        module_function

        # -> [[name, ok, detail]] for every rule that runs, in order;
        # FINAL adds the rules of `check --final`. A rule that passes
        # with a detail warns.
        def run(snapshot, final: false)
            derive = Derive.new(snapshot)
            RULES.select { final || !it.final }.map do |rule|
                verdict(rule, derive, final)
            end
        end

        def verdict(rule, derive, final)
            problems = rule.problems(derive, final)
            said = problems + rule.notes(derive)
            [rule.name, problems.empty? || (!rule.warn.nil? && !final),
             said.empty? ? "" : rule.detail(said)]
        end

        # -> [[name, detail]] of the rules that fail.
        def failures(snapshot, final: false)
            run(snapshot, final:).reject { it[1] }.map { [it[0], it[2]] }
        end

        # The write path's callable (Write.run's `checks:`): [[name,
        # detail, findings]] of the rules that fail, the shape step 6
        # compares before and after; findings nil for a rule without.
        def call(snapshot)
            derive = Derive.new(snapshot)
            compared.filter_map do |rule|
                problems = rule.compared(derive)
                next if problems.empty?

                [rule.name, rule.detail(problems),
                 FINDINGS[rule.name]&.call(derive)]
            end
        end

        def hint(name) = HINTS.fetch(name)

        # The rules step 6 compares: neither final nor REPORTED.
        def compared = RULES.reject { it.final || REPORTED.include?(it.name) }
    end
end
