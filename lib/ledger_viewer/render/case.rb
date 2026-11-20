# frozen_string_literal: true

require_relative "helpers"
require_relative "recommend"
require_relative "text"

module LedgerViewer
    module Render
        # A card's case: what is wrong, what is at stake, what will be
        # done, and what each option of a question does. facets(),
        # case_block() and option_html() of ledger-serve.py.
        class Case
            FACETS = [%w[problem Problem circle-alert],
                      %w[risk Risk shield-alert],
                      %w[plan Plan route]].freeze
            Facet = Data.define(:cls, :icon, :label, :lead, :text)

            def initialize(scope) = @scope = scope

            # What is wrong, at stake and to be done, as facets side by
            # side; a rated risk shows a ten-step meter.
            def facets(case_of)
                rows = FACETS.filter_map { facet(case_of, *it) }
                return "" if rows.empty?

                @scope.partial("ledger/facets", rows:)
            end

            # A question's case under its title: the problem, the risk,
            # what each option does, and the one recommended.
            def block(question)
                fields = Text.case_of(question["text"])
                rows = options(question, fields) + recommended(question, fields)
                lead = facets(fields)
                return lead if rows.empty?

                lead + @scope.partial("ledger/case", rows:)
            end

            # 'A = keep as is' as the code in bold, its meaning, a
            # recommended mark, and with `why` its reason.
            def option(option, rec = {}, why: false)
                code, _, meaning = option.partition(" = ")
                key = Recommend.label_fold(code)
                chosen = rec.key?(key)
                reason = chosen && why ? rec[key] : ""
                @scope.partial("ledger/option", code:, meaning:, chosen:,
                                                reason:)
            end

            private

            def facet(case_of, key, label, icon)
                text = Text.strip(case_of[key].to_s)
                return if text.empty?

                cls = "facet #{key}"
                return Facet.new(cls, icon, label, "", text) unless
                    key == "risk"

                rated(cls, icon, label, text)
            end

            def rated(cls, icon, label, text)
                rating, rest = Text.risk_rating(text)
                return Facet.new(cls, icon, label, "", text) unless rating

                band = Helpers.risk_band(rating)
                Facet.new("#{cls} #{band}", icon, label,
                          @scope.partial("ledger/rating", rating:), rest)
            end

            def options(question, fields)
                choices = question["choices"]
                return [] unless !question["items"].empty? &&
                                 choices.any? { it.include?(" = ") }

                rec = Recommend.of(fields["recommend"], choices,
                                   question["items"])
                list = choices.map { "<li>#{option(it, rec)}</li>" }.join
                ["<dt>Options</dt><dd><ul class=\"options\">#{list}</ul></dd>"]
            end

            # One answer: the reason sits under the recommended option
            # itself, so it is not said twice.
            def recommended(question, fields)
                said = fields["recommend"]
                return [] if said.nil? || said.empty?
                return [] if single?(question)

                ["<dt>Recommended</dt><dd>#{@scope.inline(said)}</dd>"]
            end

            def single?(question)
                !question["choices"].empty? && question["items"].empty? &&
                    !Helpers.filled?(question["prep"])
            end
        end
    end
end
