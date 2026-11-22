# frozen_string_literal: true

require "fileutils"

require "ledger/hooks/edit_record"

module Ledger
    module Hooks
        # Which dispatches write, and which pieces are out with one. A
        # brief writes unless its `Tools:` header names Read, Grep and
        # Glob alone or its `Permissions:` header says read-only. The
        # dispatches a session was let through with a piece are kept in
        # `dispatches/SESSION_ID` beside the journal file, one
        # `ADDRESS<TAB>P<n>` line each, so a later writing dispatch can
        # tell whether another piece is still out writing.
        module DispatchWriters
            READ_ONLY = %w[Read Grep Glob].freeze
            HEADER = /\A(Tools|Permissions):[[:space:]]*(.*)\z/

            module_function

            # The stripped lines between the BRIEF line and the first
            # blank line after it; [] when there is no BRIEF line.
            def block(prompt)
                lines = prompt.lines(chomp: true).map(&:strip)
                start = lines.index { it.match?(/\ABRIEF\b/) }
                start ? lines.drop(start + 1).take_while { !it.empty? } : []
            end

            def writes?(prompt)
                headers = block(prompt).filter_map { HEADER.match(it) }
                                       .to_h { [it[1], it[2]] }
                !(read_only_tools?(headers["Tools"]) ||
                  headers["Permissions"].to_s.match?(/read-only/i))
            end

            def read_only_tools?(value)
                tools = value.to_s.split(",").map(&:strip)
                !tools.empty? && (tools - READ_ONLY).empty?
            end

            # -> why a dispatch may not go, nil when it may; a dispatch
            # that goes with the piece OWN ([address, ref], nil for none)
            # is recorded as writing. A reader, or a writer isolated in a
            # worktree, never meets the refusal.
            def admit(input, prompt, found, session, own)
                return unless writes?(prompt)

                other = other_writer(found, session, own)
                if other && input["isolation"] != "worktree"
                    return "writes without isolation worktree while " \
                           "#{other.last} of #{other.first} is out with a " \
                           "writing dispatch"
                end
                record(session, own) if own
                nil
            end

            # The [address, ref] of another piece recorded as dispatched
            # writing that is still out, nil when there is none.
            def other_writer(found, session, own)
                (recorded(session) - [own]).find do |address, ref|
                    out?(found, address, ref)
                end
            end

            def out?(found, address, ref)
                ledger = found.find { it.address == address }
                pieces = ledger ? ledger.derive.pieces : []
                pieces.any? { "P#{it[:n]}" == ref && it[:status] == "out" }
            end

            def recorded(session)
                return [] unless EditRecord::BARE.match?(session.to_s)

                file = memory(session)
                return [] unless File.file?(file)

                File.readlines(file, chomp: true).map { it.split("\t", 2) }
            end

            def record(session, own)
                return unless EditRecord::BARE.match?(session.to_s)
                return if recorded(session).include?(own)

                file = memory(session)
                FileUtils.mkdir_p(File.dirname(file))
                File.open(file, "a") { it.puts own.join("\t") }
            end

            def memory(session)
                dir = File.dirname(EditRecord.record(session.to_s), 2)
                File.join(dir, "dispatches", session.to_s)
            end
        end
    end
end
