# frozen_string_literal: true

require "ledger/commands/goal"

module Ledger
    module Commands
        # `new PATH --goal --title --short [--context] [--date] [--carry
        # CLOSED]`: a live ledger at an address, its first Goal block, the
        # placeholder criterion D1 and the carried noticed lines.
        class New < CLI::Command
            USAGE = "PATH"
            PLACEHOLDER = "<a check something other than opinion can pass>"
            CLOSED = /\AL([1-9]\d*)\z/

            private

            def flags(parser)
                parser.on("--goal WORDS") { @opts[:goal] = it }
                parser.on("--title TITLE") { @opts[:title] = it }
                parser.on("--short SENTENCE") { @opts[:short] = it }
                parser.on("--context POINTERS") { @opts[:context] = it }
                parser.on("--date DATE") { @opts[:date] = it }
                parser.on("--carry CLOSED") { @opts[:carry] = it }
            end

            def run(path)
                address = Address.parse(path)
                row = Goal.row(@opts.merge(quote: need(:goal)), revised: false)
                refuse("#{address}: exists; refusing to overwrite") if
                    live?(address)
                create(address, row, carried_lines(@opts[:carry]))
                @out.puts address
                0
            end

            def live?(address)
                journal.db[:ledgers].where(place: address.place,
                                           name: address.name,
                                           closed_at: nil).any?
            end

            def create(address, row, carried)
                journal.transaction do
                    journal.create_ledger(address, project: project(address))
                    Write.run(journal, address, "new", @words,
                              checks: Checks) do |change|
                        seed(change, row, carried)
                    end
                end
            end

            def seed(change, row, carried)
                change.insert(:goals, **row)
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
    end
end
