# frozen_string_literal: true

require "ledger/commands/goal"

module Ledger
    module Commands
        # `new PATH --goal --title --short [--context] [--date] [--carry
        # CLOSED]`: a live ledger at an address, its first Goal block, the
        # placeholder criterion D1 and the carried noticed lines. A goal
        # not in a message of the user's is warned of unless --said-in
        # says where it was said (Heard).
        class New < CLI::Command
            include Heard

            USAGE = "PATH"
            SYNOPSIS = "PATH --goal W --title T --short S"
            SUMMARY = "open a live ledger: the goal verbatim, its title, its " \
                      "one-sentence summary"
            OPTIONS = {
                goal: ["--goal WORDS", "the user's words, verbatim"],
                title: ["--title TITLE", "a short name, at most 60 characters"],
                short: ["--short SENTENCE",
                        "the goal in one sentence, your own words"],
                context: ["--context POINTERS",
                          "the files and places it concerns"],
                date: ["--date DATE", DATE],
                carry: ["--carry CLOSED",
                        "a closed ledger (address or L<id>) whose " \
                        "noticed lines carry over"],
                confirmed: ["--confirmed WORDS",
                            "the user's words allowing a second live " \
                            "ledger in this place"],
                said_in: Heard::SAID_IN
            }.freeze
            PLACEHOLDER = "<a check something other than opinion can pass>"
            CLOSED = /\AL([1-9]\d*)\z/

            private

            def run(path)
                address = Address.parse(path)
                row = Goal.row(@opts.merge(quote: need(:goal)), revised: false)
                refuse("#{address}: exists; refusing to overwrite") if
                    live?(address)
                beside = Beside.new(journal.db, address, @opts[:confirmed])
                beside.check!
                create(address, row, carried_lines(@opts[:carry]), beside)
                report(address, row)
            end

            # The address written, then the quote's warning if any.
            def report(address, row)
                @out.puts address
                quoted!(row[:quote])
                0
            end

            def live?(address)
                journal.db[:ledgers].where(place: address.place,
                                           name: address.name,
                                           closed_at: nil).any?
            end

            def create(address, row, carried, beside)
                journal.transaction do
                    journal.create_ledger(address, project: project(address))
                    Write.run(journal, address, "new", @words,
                              checks: Checks) do |change|
                        seed(change, row, carried)
                        beside.record(change, row[:date])
                    end
                end
            end

            def seed(change, row, carried)
                change.insert(:goals, n: change.next_id("G"), **row)
                change.insert(:criteria, n: change.next_id("D"), mark: " ",
                                         text: PLACEHOLDER, evidence: "")
                carried.each { change.insert(:noticed, line: it) }
            end

            # The directory holding .claude when the ledger is in one, else
            # the ledger's own directory.
            def project(address)
                dir = address.place
                dir = File.dirname(dir) if File.basename(dir) == ".claude"
                File.basename(dir)
            end

            # The noticed lines of the closed ledger CARRY names (`L<id>`,
            # or the address its newest close had); none without --carry.
            def carried_lines(carry)
                return [] unless carry

                ledger = closed(carry) or
                    refuse("--carry #{carry}: no closed ledger")
                journal.db[:noticed].where(ledger_id: ledger[:id]).order(:id)
                       .select_map(:line)
            end

            def closed(carry)
                ledgers = journal.db[:ledgers].exclude(closed_at: nil)
                match = CLOSED.match(carry)
                return ledgers.where(id: match[1].to_i).first if match

                address = Address.parse(carry)
                ledgers.where(place: address.place, name: address.name)
                       .order(Sequel.desc(:closed_at)).first
            rescue Unknown
                nil
            end
        end

        # The live ledgers a new one would sit beside: in the same project
        # directory or its .claude/. A second ledger there is a fork the
        # user confirms in words (--confirmed), filed as their decision;
        # a first one needs no flag, and the flag with nothing beside is
        # refused rather than ignored.
        class Beside
            def initialize(db, address, words)
                @db = db
                @address = address
                @words = words&.strip
            end

            def check!
                if live.empty?
                    return unless @words

                    fail!("--confirmed: no live ledger sits here to confirm " \
                          "a second one beside")
                end
                return unless @words.nil? || @words.empty?

                raise Refused.new(refusal, rule: "second-ledger")
            end

            # The decision by user quoting the words, in the new ledger's
            # first event; nothing when it sits alone.
            def record(change, date)
                return if live.empty?

                body = "\"#{@words}\" — a second live ledger here, beside " \
                       "#{live.join(", ")}"
                change.insert(:decisions, n: change.next_id("X"), date:,
                                          body:, by: "user")
            end

            private

            def live
                @live ||= @db[:ledgers].where(closed_at: nil,
                                              place: places)
                                       .order(:place, :name)
                                       .map { address(it) }
            end

            def address(row)
                Address.new(place: row[:place], name: row[:name]).to_s
            end

            def places
                dir = @address.place
                dir = File.dirname(dir) if File.basename(dir) == ".claude"
                [dir, File.join(dir, ".claude")]
            end

            # The other path first: a request that serves or extends the
            # live goal is a Goal block there, not a second ledger.
            def refusal
                "a live ledger already sits here: #{live.join(", ")}. If " \
                    "the request serves or extends its goal, append it " \
                    "there (ledger goal #{live.first} --quote …); a second " \
                    "ledger is a fork: ask the user, then pass their words " \
                    "with --confirmed \"…\""
            end

            def fail!(message) = raise(Refused, message)
        end
    end
end
