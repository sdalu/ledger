# frozen_string_literal: true

require "fileutils"

require "ledger/hooks/edit_record"
require "ledger/hooks/ledgers"
require "ledger/outcomes"

module Ledger
    module Hooks
        # Stop: when the session's ledgers have a piece out or back and
        # their status line differs from the last one this hook showed
        # for the session, it is printed as the hook's systemMessage (the
        # text `check --peek` gives). It never blocks. The last text
        # shown is kept in `status/SESSION_ID` beside the journal file.
        # It does refuse while a piece is ready and started (planned,
        # awaiting no word, not held) in the session's ledgers: the stop
        # is sent back naming it, until it goes out or is held with a
        # reason, so that a piece whose wait just settled is not left
        # unsent.
        module StatusStop
            LIVE = %w[out back].freeze

            module_function

            def call(payload)
                id = payload["session_id"].to_s
                return Answer.pass unless EditRecord::BARE.match?(id)

                found = Ledgers.read(payload)
                ready = unsent(found)
                return send_back(payload, ready) unless ready.empty?

                show(payload, id, lines(found))
            end

            # The status TEXT, shown once per distinct text.
            def show(payload, id, text)
                return through(payload, "nothing in flight") if text.empty?
                return through(payload, "status unchanged") if
                    shown(id) == text

                remember(id, text)
                through(payload, "status shown")
                Answer.json(systemMessage: text)
            end

            # The refs of the ready, started and unheld pieces of FOUND.
            def unsent(found)
                found.flat_map do |ledger|
                    derive = ledger.derive
                    derive.pieces.select { derive.ready?(it) }
                          .map { derive.ref(it) }
                end
            end

            # The stop sent back naming REFS, recorded with the reason.
            def send_back(payload, refs)
                list = refs.join(", ")
                Outcomes.hook("status-stop", payload, "sent-back",
                              "ready and started: #{list}")
                Answer.refuse("ready and started, not sent: #{list}; send " \
                              "it or hold it with a reason (piece --hold)")
            end

            # The stop let through, recorded with WHY (Outcomes.hook).
            def through(payload, why)
                Outcomes.hook("status-stop", payload, "let-through", why)
                Answer.pass
            end

            # The status lines of the ledgers with a piece out or back.
            def lines(found)
                found.select { |ledger| live?(ledger.derive) }
                     .map(&:status_line).join("\n")
            end

            def live?(derive)
                derive.pieces.any? { LIVE.include?(it[:status]) }
            end

            # The memory file of session ID, beside the journal.
            def memory(id)
                dir = File.dirname(EditRecord.record(id), 2)
                File.join(dir, "status", id)
            end

            def shown(id)
                file = memory(id)
                File.file?(file) ? File.read(file).chomp : nil
            end

            # Written to a temp path and renamed: an interrupt leaves the
            # old text or the new.
            def remember(id, text)
                file = memory(id)
                FileUtils.mkdir_p(File.dirname(file))
                tmp = "#{file}.#{Process.pid}"
                File.write(tmp, "#{text}\n")
                File.rename(tmp, file)
            end
        end
    end
end
