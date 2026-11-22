# frozen_string_literal: true

module Ledger
    module Commands
        # `piece --report FILE`: a helper's report, the input of its last
        # hand-back, stored as its first line (the status word, such as
        # DONE_WITH_CONCERNS) and up to LINES lines after it, trailing
        # blank ones dropped. A piece keeps one report: a later one
        # replaces it. FILE is read before the write opens (`-` for
        # stdin), so a refusal leaves no event.
        class PieceReport
            LINES = 12

            # {status:, body:} of the text in FILE.
            def self.read(file)
                lines = text(file).lines(chomp: true)
                status = lines.first.to_s.strip
                if status.empty?
                    raise Refused, "--report #{file}: the first line, the " \
                                   "status word, is empty"
                end
                body = lines.drop(1).first(LINES)
                body.pop while body.last&.strip&.empty?
                { status:, body: (body.join("\n") unless body.empty?) }
            end

            def self.text(file)
                return $stdin.read.force_encoding(Encoding::UTF_8) if
                    file == "-"

                File.read(file, encoding: Encoding::UTF_8)
            rescue SystemCallError => e
                raise Refused, "--report cannot read #{file}: #{e.message}"
            end

            # REPORT, the {status:, body:} read, or nil when none was given.
            def initialize(change, db, report)
                @change = change
                @db = db
                @report = report
            end

            # Stores the report on PIECE (a row id), replacing the one it
            # held.
            def store(piece)
                return unless @report

                held = @db[:piece_reports].where(piece_id: piece).get(:id)
                if held
                    @change.update(:piece_reports, held,
                                   event_id: @change.event_id, **@report)
                else
                    @change.insert(:piece_reports, piece_id: piece, **@report)
                end
            end
        end
    end
end
