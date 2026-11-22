# frozen_string_literal: true

require_relative "reading"
require_relative "recommend"
require_relative "text"

module LedgerViewer
    module Render
        # A card's case: what is wrong, what will be done, and what each
        # option of a question does; what is at stake is the card's RAID
        # line (Raid).
        class Case
            FACETS = [%w[problem Problem circle-alert],
                      %w[plan Plan route]].freeze
            Facet = Data.define(:cls, :icon, :label, :text)

            def initialize(scope) = @scope = scope

            # A piece's or a question's case as {key => text}: problem,
            # risk (its text, the rating leading it), plan, recommend.
            def self.fields(item)
                { "problem" => item["problem"],
                  "risk" => item["risk"]&.fetch("text"), "plan" => item["plan"],
                  "recommend" => item["recommend"] }
            end

            # What is wrong and what is to be done, as facets side by
            # side. `item` is a piece or a question.
            def facets(item)
                case_of = Case.fields(item)
                rows = FACETS.filter_map { facet(case_of, *it) }
                return "" if rows.empty?

                @scope.partial("ledger/facets", rows:)
            end

            # A question's case under its title: the problem, what each
            # option does, and the one recommended.
            def block(question)
                fields = Case.fields(question)
                rows = options(question, fields) + recommended(question, fields)
                lead = facets(question)
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

            # The commits that landed a piece, a muted line of monospace
            # ids; "" when it holds none.
            def commits(piece)
                ids = piece.fetch("commits", [])
                return "" if ids.empty?

                list = ids.map { "<code>#{Text.escape(it)}</code>" }.join(", ")
                %(<p class="no-picture commits">Commits: #{list}</p>)
            end

            private

            def facet(case_of, key, label, icon)
                text = Text.strip(case_of[key].to_s)
                return if text.empty?

                Facet.new("facet #{key}", icon, label, text)
            end

            def options(question, fields)
                choices = Reading.options(question)
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
                    !question["preparing"]
            end
        end
    end
end
