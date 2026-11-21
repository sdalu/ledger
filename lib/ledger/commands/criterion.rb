# frozen_string_literal: true

module Ledger
    module Commands
        # `criterion PATH D<n> (--met E | --unmet W | --text T)` and
        # `criterion PATH new --text T`: mark a criterion met or not met,
        # reword it, or add one.
        class Criterion < CLI::Command
            USAGE = "PATH ID"
            SYNOPSIS = "PATH new|D<n> --text T|--met E|--unmet W"
            SUMMARY = "add a Done when criterion, reword one, or mark it met " \
                      "or not met"
            OPTIONS = {
                met: ["--met EVIDENCE", "mark it met, with the evidence"],
                unmet: ["--unmet WHY", "mark it not met, with why"],
                text: ["--text TEXT", "its words; new needs them"]
            }.freeze
            ID = /\AD[1-9]\d*\z/
            EMPTY = "--met takes the evidence, --unmet the reason, --text " \
                    "the words; none may be empty"

            private

            def flags(parser)
                dry_run(parser)
            end

            def run(path, id)
                return add(path) if id == "new"

                unless ID.match?(id)
                    refuse("the target is D<n>, or `new` with --text")
                end
                result = write(path, own: id) { |change| mark(change, id) }
                emit(result, path,
                     lines: [Render::Markdown.line(result.after, id)])
                0
            end

            def add(path)
                refuse("new takes --text alone") if @opts[:met] || @opts[:unmet]
                text = line(@opts[:text], "--text")
                add_item(path, "D", :criteria, mark: " ", text:)
            end

            def mark(change, id)
                row = change.resolve(id).last
                change.update(:criteria, row[:id], **columns)
            rescue Unknown
                refuse("#{id} is not a criterion under Done when")
            end

            # The columns a D<n> command sets: a new text, or a mark.
            def columns
                met, unmet, text = @opts.values_at(:met, :unmet, :text)
                refuse("--text goes alone, without --met or --unmet") if
                    text && (met || unmet)
                refuse("give one of --met, --unmet, --text") unless
                    [met, unmet, text].one?
                return { text: line(text, "--text") } if text

                marked(met, unmet)
            end

            def marked(met, unmet)
                value = (met || unmet).to_s.strip
                refuse(EMPTY) if value.empty?
                return { mark: "x", evidence: value, why: nil } if met

                { mark: "-", why: value, evidence: nil }
            end
        end
    end
end
