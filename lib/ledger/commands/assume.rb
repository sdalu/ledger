# frozen_string_literal: true

module Ledger
    module Commands
        # `assume PATH 'TEXT — CHECK' [--see IDS] [--for IDS]`: an
        # assumption, what the plan takes as true without having checked
        # it, and how it will be checked, split at the first ` — `; its id
        # the next A<n>, open. `assume PATH A<n> --confirmed-by F<n> |
        # --refuted-by F<n> | --for IDS | --reopen`: settled by a fact of
        # the ledger, the pieces and questions resting on it replaced, or
        # open again.
        class Assume < CLI::Command
            USAGE = "PATH TEXT"
            SYNOPSIS = "PATH 'TEXT — CHECK' [--see IDS] [--for IDS] | " \
                       "PATH A<n> --confirmed-by F<n>|--refuted-by F<n>|" \
                       "--for IDS|--reopen"
            SUMMARY = "an assumption and how it will be checked, split at " \
                      "the first ' — '; or one settled by a fact, " \
                      "relinked or reopened"
            OPTIONS = {
                see: ["--see IDS", "C/D/F/P ids: what it rests on"],
                for: ["--for IDS", "P<n>,O<n>,...: what rests on it"],
                confirmed: ["--confirmed-by FACT",
                            "A<n>: F<n>, the fact that confirmed it"],
                refuted: ["--refuted-by FACT",
                          "A<n>: F<n>, the fact that refuted it"]
            }.freeze
            SHAPE = /\A(?<text>.+?) — (?<check>\S.*)\z/
            ID = /\AA[1-9]\d*\z/
            # What A<n> takes, one at a time.
            MARKS = %i[confirmed refuted for reopen].freeze

            private

            def flags(parser)
                parser.on("--reopen", "A<n>: open again, its fact gone") do
                    @opts[:reopen] = true
                end
                dry_run(parser)
            end

            def run(path, text)
                return mark(path, text) if ID.match?(text)

                if @opts.keys.intersect?(MARKS - [:for])
                    refuse("--confirmed-by, --refuted-by and --reopen name " \
                           "an assumption: assume PATH A<n>")
                end
                add(path, text)
            end

            def add(path, text)
                match = SHAPE.match(line(text, "the assumption")) or
                    refuse("an assumption ends with — and how it will be " \
                           "checked")
                links = [list(:see), list(:for)]
                result = write(path) { insert(it, match, *links) }
                report(result, path, result.value, first: result.value)
            end

            # The new A<n>, open, what it rests on and what rests on it ->
            # its id.
            def insert(change, match, sees, ids)
                ref = "A#{change.next_id("A")}"
                change.own = ref
                id = change.insert(:assumptions, n: ref[1..].to_i,
                                                 text: match[:text],
                                                 check: match[:check],
                                                 state: "open")
                AssumptionSees.new(change, id).insert(sees)
                links(change, id, ids)
                ref
            end

            def mark(path, id)
                refuse("--see goes with a new assumption") if @opts.key?(:see)
                apply = marker(given_mark)
                result = write(path, own: id) do |change|
                    apply.call(change, assumption(change, id))
                end
                report(result, path, id)
            end

            # The one of MARKS given; refused unless exactly one is.
            def given_mark
                given = MARKS.select { @opts.key?(it) }
                return given.first if given.one?

                refuse("give one of --confirmed-by F<n>, --refuted-by F<n>, " \
                       "--for IDS, --reopen")
            end

            # What the one mark given does to the row, its value checked
            # before the write.
            def marker(mark)
                unless mark == :for
                    return AssumeMark.new(mark, @opts[mark]).method(:apply)
                end

                ids = list(:for)
                ->(change, row) { links(change, row[:id], ids) }
            end

            def links(change, id, ids)
                AssumptionLinks.new(change, journal.db, id).replace(ids)
            end

            def report(result, path, ref, first: nil)
                line = Render::Markdown.line(result.after, ref)
                emit(result, path, first:, lines: [line])
                0
            end

            # The ids --NAME gives, each once, or nil without it.
            def list(name)
                return unless @opts.key?(name)

                ids = @opts[name].split(",", -1).map(&:strip)
                refuse("--#{name} is empty") if ids.empty? || ids.any?(&:empty?)
                ids.uniq
            end

            def assumption(change, id)
                change.resolve(id).last
            rescue Unknown
                refuse("#{id} is not an assumption of this ledger")
            end
        end

        # `assume PATH A<n> --confirmed-by F<n> | --refuted-by F<n> |
        # --reopen`: the state and the fact that settled it, set together
        # and cleared together.
        class AssumeMark
            FACT = /\AF[1-9]\d*\z/

            # MARK :confirmed, :refuted or :reopen (:for is the links'),
            # VALUE the F<n> given, checked before the write.
            def initialize(mark, value)
                @mark = mark
                @ref = fact_ref(value) unless mark == :reopen
            end

            def apply(change, row)
                return reopen(change, row) if @mark == :reopen

                unless row[:state] == "open"
                    refuse("A#{row[:n]} is #{row[:state]} already; " \
                           "--reopen it first")
                end
                change.update(:assumptions, row[:id], state: @mark.to_s,
                                                      fact_id: fact(change))
            end

            private

            def fact_ref(value)
                ref = value.to_s.strip
                refuse("--#{@mark}-by is empty") if ref.empty?
                return ref if FACT.match?(ref)

                refuse("--#{@mark}-by takes a fact, F<n>, not #{ref}")
            end

            def fact(change)
                change.resolve(@ref).last[:id]
            rescue Unknown
                refuse("#{@ref} is not a fact of this ledger")
            end

            def reopen(change, row)
                refuse("A#{row[:n]} is open already") if row[:state] == "open"
                change.update(:assumptions, row[:id], state: "open",
                                                      fact_id: nil)
            end

            def refuse(message) = raise(Refused, message)
        end

        # What one assumption rests on: its `— see:` rows, in the order
        # given, each naming one constraint, criterion, fact or piece.
        class AssumptionSees
            COLUMNS = { "C" => :constraint_id, "D" => :criterion_id,
                        "F" => :fact_id, "P" => :piece_id }.freeze

            def initialize(change, assumption_id)
                @change = change
                @id = assumption_id
            end

            def insert(ids)
                rows = (ids || []).map { target(it) }
                rows.each_with_index do |(column, row), position|
                    @change.insert(:assumption_sees, assumption_id: @id,
                                                     position:,
                                                     column => row[:id])
                end
            end

            private

            def target(id)
                column = COLUMNS[id[0]] or refuse(id)
                [column, @change.resolve(id).last]
            rescue Unknown
                refuse(id)
            end

            def refuse(id)
                raise Refused, "--see: #{id} is not a constraint, criterion, " \
                               "fact or piece of this ledger"
            end
        end

        # The pieces and questions resting on one assumption: its links,
        # replaced as a whole.
        class AssumptionLinks
            TARGET = /\A[PO][1-9]\d*\z/
            COLUMNS = { "P" => :piece_id, "O" => :question_id }.freeze

            def initialize(change, db, assumption_id)
                @change = change
                @db = db
                @id = assumption_id
            end

            # IDS ("P3", "O2") resolved in the ledger, then every link the
            # assumption had dropped and one made per id; nil changes
            # nothing.
            def replace(ids)
                return unless ids

                rows = ids.map { target(it) }
                @db[:assumption_links].where(assumption_id: @id)
                                      .select_map(:id)
                                      .each { drop(it) }
                rows.each do |column, row|
                    @change.insert(:assumption_links, assumption_id: @id,
                                                      column => row[:id])
                end
            end

            private

            def drop(id) = @change.delete(:assumption_links, id)

            # [the link's column, the row] of a P<n> or O<n>.
            def target(id)
                refuse(id) unless TARGET.match?(id)
                [COLUMNS.fetch(id[0]), @change.resolve(id).last]
            rescue Unknown
                refuse(id)
            end

            def refuse(id)
                raise Refused, "--for: #{id} is not a piece or question of " \
                               "this ledger"
            end
        end
    end
end
