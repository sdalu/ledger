# frozen_string_literal: true

module Ledger
    module Text
        # The ANNOUNCE block a dispatch is announced with (the delegation
        # skill's hook hands it to `piece --announce`): the line ANNOUNCE,
        # then one `LABEL: text` line for each of WHAT, WHY, WHICH, RISK
        # and MODE, in any order, up to the first blank line.
        #
        #     Announce.parse("ANNOUNCE\nWHAT: w\nWHY: y\nWHICH: sonnet, " \
        #                    "effort: low — highest axis: stakes (low)\n" \
        #                    "RISK: 2/10 — r\nMODE: attended; spawn: no\n")
        #     # => #<data Announce::Block model="sonnet", effort="low", ...>
        module Announce
            LABELS = %w[WHAT WHY WHICH RISK MODE].freeze
            LINE = /\A(?<label>[A-Z]+):[ \t]*(?<text>.*)\z/
            # MODEL[, effort: E][ — highest axis: AXIS (LEVEL)]; the model
            # is any name, a vendor's on a codex call.
            WHICH = /\A(?<model>[^,\s—]+)
                     (?:,\s*effort:\s*(?<effort>low|medium|high|xhigh|max))?
                     (?:\s+—\s+highest\ axis:\s*(?<axis>[^()]*?)
                        \s*\((?<level>low|mid|high)\))?\z/ix
            # The delegation scripts' RATED: "N/10 — what".
            RATED = %r{\A(10|[0-9])/10 — \S}
            WHICH_FORM = "MODEL[, effort: E] — highest axis: AXIS " \
                         "(low|mid|high)"
            MODES = { "attended" => true, "unattended" => false }.freeze

            # The block's fields, as the piece_assessments columns name
            # them.
            Block = Data.define(:what, :why, :model, :effort, :axis,
                                :axis_level, :risk_rating, :risk_text,
                                :mode, :mode_attended, :block)

            module_function

            # TEXT -> a Block; Refused, with a sentence naming what is
            # wrong, when TEXT is no announce block.
            def parse(text)
                lines = lines(text)
                fields = labelled(lines.drop(1))
                Block.new(what: fields["WHAT"], why: fields["WHY"],
                          **which(fields["WHICH"]), **risk(fields["RISK"]),
                          **mode(fields["MODE"]),
                          block: lines.join("\n") << "\n")
            end

            # The block's lines, up to the first blank one, ANNOUNCE
            # first.
            def lines(text)
                lines = text.to_s.lines(chomp: true)
                            .take_while { !it.strip.empty? }
                unless lines.first&.strip == "ANNOUNCE"
                    refuse("the block does not open with the line ANNOUNCE.")
                end
                lines
            end

            # {LABEL => text} of the labelled lines, each label once.
            def labelled(lines)
                fields = lines.each_with_object({}) do |line, out|
                    label, text = label(line)
                    refuse("the block gives #{label} twice.") if
                        out.key?(label)
                    out[label] = text
                end
                missing = LABELS - fields.keys
                return fields if missing.empty?

                refuse("the block has no #{listed(missing, "or")} line; it " \
                       "needs #{listed(LABELS, "and")}.")
            end

            # ["A", "B", "C"], "or" -> "A, B or C".
            def listed(words, conjunction)
                *head, last = words
                return last if head.empty?

                "#{head.join(", ")} #{conjunction} #{last}"
            end

            def label(line)
                match = LINE.match(line.strip)
                unless match && LABELS.include?(match[:label])
                    refuse("the block's line \"#{line.strip}\" is not " \
                           "LABEL: text, with a label of " \
                           "#{listed(LABELS, "or")}.")
                end
                text = match[:text].strip
                refuse("the block's #{match[:label]} line is empty.") if
                    text.empty?
                [match[:label], text]
            end

            # The model, the effort and the highest axis with its level;
            # an effort or an axis left out is nil.
            def which(text)
                match = WHICH.match(text) or
                    refuse("the WHICH line \"#{text}\" does not read " \
                           "#{WHICH_FORM}.")
                axis = match[:axis]&.strip&.downcase
                { model: match[:model], effort: match[:effort]&.downcase,
                  axis: (axis unless axis.to_s.empty?),
                  axis_level: match[:level]&.downcase }
            end

            # The rating, nil when the RISK line gives no N/10, and the
            # line whole.
            def risk(text)
                rating = RATED.match(text)&.then { it[1].to_i }
                { risk_rating: rating, risk_text: text }
            end

            # The MODE line raw, and whether its first word says attended.
            def mode(text)
                word = text.split(";").first.to_s.strip.split.first.to_s
                attended = MODES[word.downcase]
                if attended.nil?
                    refuse("the MODE line opens with \"#{word}\", not " \
                           "attended or unattended.")
                end
                { mode: text, mode_attended: attended }
            end

            def refuse(message) = raise(Refused, message)
        end
    end
end
