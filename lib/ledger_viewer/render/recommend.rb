# frozen_string_literal: true

require_relative "terms"
require_relative "text"

module LedgerViewer
    module Render
        # Which options a question's `— recommend:` picks. recommended()
        # and label_fold() of ledger.py.
        module Recommend
            module_function

            # A label as compared: case and spacing folded away.
            def label_fold(label)
                Text.words(label).join(" ").downcase(:fold)
            end

            # {folded label => why} the `— recommend:` `rec` picks among
            # `opts` (per item of `its` from two items on: each item's
            # pick, with no why); {} when it names no option.
            def of(rec, opts, its)
                rec = rec.to_s
                labels = opts.map { label_fold(Terms.option_code(it)) }.uniq
                return per_item(rec, labels, its) if its.length >= 2

                label = pick(rec.downcase(:fold), labels)
                label ? { label => Text.strip(rec[(label.length + 1)..]) } : {}
            end

            # The longest label the folded `low` starts with or is.
            def pick(low, labels)
                labels.sort_by { -it.length }.find do |name|
                    low.start_with?("#{name},") || low == name
                end
            end

            def per_item(rec, labels, its)
                codes = its.map { Terms.option_code(it) }
                picks = rec.split(",").map { Text.strip(it) }
                           .reject(&:empty?)
                picks.each_with_object({}) do |pair, out|
                    code = codes.find { pair.start_with?("#{it} ") }
                    name = code && label_fold(pair[code.length..])
                    out[name] = "" if name && labels.include?(name)
                end
            end
        end
    end
end
