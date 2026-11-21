# frozen_string_literal: true

module Ledger
    module Text
        # The options of a question: "LABEL = effect; cost" strings, the
        # grammar `ask` and `choice` keep, and the add / drop edits of
        # `choice`. Pure: lists and strings in, a list or a refusal out.
        module Options
            LABEL_MAX  = 24
            DROP_WORDS = %w[drop ignore].freeze
            ESCAPES    = { "\\" => "\\\\", "\n" => "\\n",
                           "\t" => "\\t", "\r" => "\\r" }.freeze

            COLON      = "an option with a colon; one answer per item is " \
                         "`items: a | b`"
            NO_CHOICES = "`items:` without `choices:`"
            DROP       = "drop/ignore is not an answer: the viewer always " \
                         "offers it"

            module_function

            # "a | b" -> ["a", "b"]: the parts of a `choices:` or `items:`
            # value, blank parts gone.
            def split(value)
                value.split("|").map(&:strip).reject(&:empty?)
            end

            # "A = keep it; costs a day" -> ["A", "keep it", "costs a day"].
            def parts(option)
                label, _, rest = option.partition(" = ")
                effect, _, cost = rest.partition("; ")
                [label.strip, effect.strip, cost.strip]
            end

            # "A = keep as is" -> "A"; an option without a meaning is its
            # own code.
            def code(option) = option.split(" = ", 2).first.to_s.strip

            # A label as compared: case and spacing folded away.
            def fold(label) = label.split.join(" ").downcase(:fold)

            # A string as the refusal messages quote it: single quotes, double
            # when it holds one and no double, backslash escapes.
            def repr(text)
                quote = text.include?("'") && !text.include?('"') ? '"' : "'"
                body = text.gsub(/[\\\n\t\r]/, ESCAPES)
                body = body.gsub("'", "\\\\'") if quote == "'"
                "#{quote}#{body}#{quote}"
            end

            # Why the options OPTS break the grammar, or nil.
            def problem(opts)
                opts.each { |o| (why = option_problem(o)) and return why }
                if dup?(opts.map { fold(parts(it).first) })
                    "two options share a label once case and spacing are " \
                        "folded; rename one"
                elsif dup?(opts.map { fold(parts(it)[1]) }.reject(&:empty?))
                    "two options share one effect; say what each does " \
                        "differently, or drop one"
                end
            end

            # The options of OPTS with TEXT (`LABEL = effect; cost`) added:
            # -> [options, nil], or [nil, refusal].
            def add(opts, text)
                return [nil, "--add takes `LABEL = what it does`"] \
                    if text.strip.empty? || !text.include?(" = ")

                edited(opts + [text.strip])
            end

            # The options of OPTS without the one labelled LABEL, folded:
            # -> [options, nil], or [nil, refusal].
            def drop(opts, label)
                keep = opts.reject { fold(parts(it).first) == fold(label) }
                return edited(keep) unless keep.size == opts.size

                names = opts.map { parts(it).first }.join(", ")
                [nil, "--drop #{label}: no such option (#{names})"]
            end

            # What is wrong with the shape of OPTS and ITEMS, as the
            # remarks a check prefixes with the question's id.
            def shape_problems(opts, items)
                [(COLON if opts.any? { code(it).include?(":") }),
                 (NO_CHOICES if items.any? && opts.empty?),
                 (DROP if items.empty? && drop_word?(opts))].compact
            end

            def dup?(list) = list.uniq.size != list.size

            def edited(opts)
                why = problem(opts)
                why ? [nil, why] : [opts, nil]
            end

            def drop_word?(opts)
                opts.any? { DROP_WORDS.include?(code(it).downcase) }
            end

            def option_problem(option)
                label, = parts(option)
                if label.length > LABEL_MAX || label.include?(";") ||
                   label.include?("?")
                    "option #{repr(label)}: a label is at most " \
                        "#{LABEL_MAX} characters without `;` or `?`; put " \
                        "the detail in its effect (`LABEL = what it does`)"
                elsif option.partition(" = ").last.include?(" = ")
                    "option #{repr(label)}: its effect holds ` = `; one " \
                        "`LABEL = effect` each"
                end
            end
        end
    end
end
