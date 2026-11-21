# frozen_string_literal: true

require_relative "options"

module Ledger
    module Text
        # The picker grammar of a question (rules G1-G5, G7, G9): `choices:`
        # is two to eight options "label = effect; cost", `items:` one
        # answer per item, `recommend:` the pick. Pure: the question's
        # fields in, problems and warnings out.
        module Picker
            OPTIONS_WARN = 7
            OPTIONS_MAX  = 8
            FAMILY       = /\A([A-Z])[0-9]{1,2}\z/
            QUOTED       = /`[^`]*`|"[^"]*"|“[^”]*”/
            LABEL_TOKEN  = /[\p{Word}′'’]+/
            REPLACES     = "`ledger ask … --replaces O<n>`"

            G4_ASKS = "the question asks more than one thing (G4: one `?` " \
                      "outside backticks and quotes); ask each in its own " \
                      "question"
            G4_EFFECT = "its effect holds a `?` (G4); say what it does, not " \
                        "what it asks"
            G7_ITEMS = "`items:` without `choices:` (G7); give the answers " \
                       "offered per item"

            module_function

            # -> [problems, warnings] for a question: DETAIL its sentence,
            # OPTS its options, ITEMS its items, RECOMMEND its pick; READY
            # is false while a piece still prepares it (no pick is asked
            # of it then).
            def problems(detail:, opts:, items: [], recommend: "", ready: true)
                out = []
                out << G4_ASKS if question_marks(detail) > 1
                out << G7_ITEMS if items.any? && opts.empty?
                return [out, []] if opts.empty?

                out.concat(grammar(opts))
                out.concat(pick(opts, items, recommend)) if ready
                [out, warnings(opts)]
            end

            # How many "?" TEXT holds outside backticks and double quotes.
            def question_marks(text) = text.gsub(QUOTED, "").count("?")

            # Whether the label LONG holds the label SHORT as a run of
            # whole tokens.
            def contains_label?(long, short)
                big = tokens(long)
                small = tokens(short)
                !small.empty? && small.size < big.size &&
                    big.each_cons(small.size).any?(small)
            end

            # The label and effect of each option, as G9 compares them:
            # two open questions offering the same set ask the same thing.
            def signature(opts)
                opts.to_set do |option|
                    label, effect, = Options.parts(option)
                    [Options.fold(label), effect.downcase.split.join(" ")]
                end
            end

            # QUESTIONS: [[id, opts]] of the open questions -> the G9
            # messages, one per group offering the same options.
            def duplicates(questions)
                groups = questions.reject { it.last.empty? }
                                  .group_by { signature(it.last) }
                groups.values.select { it.size > 1 }.map do |group|
                    "#{group.map(&:first).join(" and ")} offer the same " \
                        "options (G9); one question, or #{REPLACES}"
                end
            end

            def tokens(label) = Options.fold(label).scan(LABEL_TOKEN)

            def warnings(opts)
                return [] unless opts.size.between?(OPTIONS_WARN, OPTIONS_MAX)

                ["#{opts.size} options (G3: seven or eight is a lot to weigh)"]
            end

            def grammar(opts)
                labels = opts.map { Options.parts(it).first }
                families(labels) + holds(labels) + count(opts) + effects(opts)
            end

            def effects(opts)
                opts.filter_map do |option|
                    label, effect, = Options.parts(option)
                    next unless question_marks(effect).positive?

                    "option #{Options.repr(label)}: #{G4_EFFECT}"
                end
            end

            def families(labels)
                groups = labels.filter_map { FAMILY.match(it) }
                               .group_by { it[1] }
                split = groups.select { |_, m| m.size >= 2 }.keys.sort
                return [] if split.size < 2

                ["options of families #{split.join(", ")} in one question " \
                 "(G1); one question per family, #{REPLACES}"]
            end

            def holds(labels)
                labels.product(labels).filter_map do |a, b|
                    next if a == b || !contains_label?(a, b)

                    "option #{Options.repr(a)} holds the option " \
                        "#{Options.repr(b)} as a whole token (G2); name " \
                        "each option apart"
                end
            end

            def count(opts)
                if opts.size < 2
                    ["one option is no choice (G3); give two to eight"]
                elsif opts.size > OPTIONS_MAX
                    ["#{opts.size} options (G3: two to eight); split the " \
                     "question, #{REPLACES}"]
                else
                    []
                end
            end

            def pick(opts, items, recommend)
                return [] if recommend.empty?

                why = Recommend.problem(recommend, opts, items)
                why ? ["#{why} (G5)"] : []
            end
        end

        # A question's picker as its card offers it.
        module Card
            NONE = "picker %s: none (no choices:, the user answers in words)"

            module_function

            # The picker of an Open question as its card offers it, a line
            # each; PROBLEMS and WARNINGS as `problems` returned them.
            def lines(oid, opts, items, recommend, issues)
                return [NONE % oid] if opts.empty?

                picks = Recommend.recommended(recommend, opts, items)
                [head(oid, opts, items), *option_lines(opts, picks),
                 *per_item(items, recommend),
                 *issues.last.map { "  warning: #{it}" },
                 *issues.first.map { "  refused: #{it}" }]
            end

            def head(oid, opts, items)
                text = "picker #{oid}: #{opts.size} options"
                return text if items.empty?

                "#{text} for each of #{Recommend.codes(items).join(", ")}"
            end

            def option_lines(opts, picks)
                opts.map do |option|
                    label, effect, cost = Options.parts(option)
                    star = "  <- recommended" if picks.key?(Options.fold(label))
                    cost = "; #{cost}" unless cost.empty?
                    "  #{label} = #{effect}#{cost}#{star}"
                end
            end

            def per_item(items, recommend)
                return [] unless items.size >= 2 && !recommend.empty?

                ["  recommended: #{recommend}"]
            end
        end

        # What a question's `recommend:` names among its options.
        module Recommend
            module_function

            # Why the recommend REC does not name an option of OPTS with its
            # why (per item of ITEMS from two on: `S4 A, S5 B`, one pair for
            # each), or nil.
            def problem(rec, opts, items)
                labels = folded(opts)
                return per_item_problem(rec, labels, items) if items.size >= 2

                single_problem(rec, opts, labels)
            end

            # -> { folded label => why } the recommend REC picks among OPTS
            # (per item from two items on: each item's pick, with no why);
            # {} when it names no option.
            def recommended(rec, opts, items)
                labels = folded(opts)
                if items.size >= 2
                    return per_item_picks(rec, labels, codes(items))
                end

                low = rec.downcase(:fold)
                label = by_length(labels).find do |name|
                    low.start_with?("#{name},") || low == name
                end
                label ? { label => rec[(label.length + 1)..].to_s.strip } : {}
            end

            def folded(opts)
                opts.map { Options.fold(Options.parts(it).first) }
            end

            def codes(items) = items.map { Options.code(it) }

            # LABELS longest first, ties in their given order.
            def by_length(labels)
                labels.each_with_index.sort_by { |l, i| [-l.length, i] }
                      .map(&:first)
            end

            # -> [[pair, the item code it starts with, or nil]].
            def per_item_pairs(rec, codes)
                rec.split(",").map(&:strip).reject(&:empty?).map do |pair|
                    [pair, codes.find { pair.start_with?("#{it} ") }]
                end
            end

            def per_item_problem(rec, labels, items)
                codes = codes(items)
                seen = Hash.new(0)
                per_item_pairs(rec, codes).each do |pair, code|
                    why = pair_problem(pair, code, labels, codes)
                    return why if why

                    seen[code] += 1
                end
                gaps(codes.reject { seen[it] == 1 })
            end

            def gaps(missing)
                return nil if missing.empty?

                "recommend: one option for each item, not for " \
                    "#{missing.join(", ")}"
            end

            def pair_problem(pair, code, labels, codes)
                if code.nil?
                    "recommend: #{Options.repr(pair)} starts with no item " \
                        "(#{codes.join(", ")}); `#{codes.first} A, " \
                        "#{codes.last} B`"
                elsif !labels.include?(Options.fold(pair[code.length..]))
                    "recommend: #{Options.repr(pair)} names no option"
                end
            end

            def per_item_picks(rec, labels, codes)
                pairs = per_item_pairs(rec, codes)
                pairs.each_with_object({}) do |(pair, code), out|
                    fold = code && Options.fold(pair[code.length..])
                    out[fold] = "" if fold && labels.include?(fold)
                end
            end

            def single_problem(rec, opts, labels)
                low = rec.downcase(:fold)
                by_length(labels).each do |label|
                    next unless low == label ||
                                low.start_with?("#{label},", "#{label} ")
                    return nil if why?(low, rec, label)

                    return no_why(rec, Options.parts(opts[labels.index(label)]))
                end
                "recommend: #{Options.repr(rec.split.first.to_s)} is not an " \
                    "option; `LABEL, why` with a label of choices"
            end

            def no_why(rec, parts)
                "recommend: #{Options.repr(rec)} gives no why; " \
                    "`#{parts.first}, why`"
            end

            def why?(low, rec, label)
                low.start_with?("#{label}, ") &&
                    !rec[(label.length + 2)..].strip.empty?
            end
        end
    end
end
