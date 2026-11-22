# frozen_string_literal: true

require "ledger/asked_since"
require "ledger/commands/decide"
require "ledger/commands/heard"

module Ledger
    module Commands
        # `--take N…` of `answer` and `word`: the viewer's entries that
        # carried the user's words, taken in the command's own event.
        # Without them, the user's word must follow the ask in this
        # session's transcript (Heard).
        module Taking
            include Heard

            ENTRY = /\AN([1-9]\d*)\z/
            TIME = "%Y-%m-%dT%H:%M:%S"

            private

            # `--take N1,N2`, or the flag given again.
            def take_flag(parser)
                parser.on("--take IDS",
                          "N<n>,... the viewer's entries it files") do |ids|
                    (@opts[:take] ||= []).concat(ids.split(/[,\s]+/))
                end
            end

            def takes = (@opts[:take] || []).reject(&:empty?).uniq

            # The entries IDS name, refused when one is unknown or was
            # taken before: its words were filed there.
            def entries(change, ids)
                rows = ids.to_h { [it, entry(change, it)] }
                bad = rows.select { |_, row| row.nil? }.keys
                refuse("no inbox entry #{bad.join(", ")}") if bad.any?
                rows.each { |id, row| refuse_taken(id, row) }
                rows.values
            end

            def entry(change, id)
                match = ENTRY.match(id) or return
                journal.db[:inbox_entries].where(ledger_id: change.ledger_id,
                                                 n: match[1].to_i).first
            end

            def refuse_taken(id, row)
                return unless row[:taken_id]

                at = journal.db[:events].where(id: row[:taken_id]).get(:at)
                time = Time.at(at / 1000).strftime(TIME)
                refuse("#{id} was already taken at #{time}: another " \
                       "session filed it")
            end

            # ASKED, [table, row id] of the item asking the word, is
            # checked when no entry is taken.
            def take(change, ids, asked: nil)
                heard!(AskedSince.row(journal.db, *asked)) if asked &&
                                                              ids.empty?
                entries(change, ids).each do |row|
                    change.update(:inbox_entries, row[:id],
                                  taken_id: change.event_id)
                end
            end

            # `taken: N1; pending: N2`, after a write that took IDS.
            def take_line(snapshot, ids)
                left = snapshot.inbox_entries.reject { it[:taken_id] }
                               .filter_map { "N#{it[:n]}" if it[:n] }
                "taken: #{ids.join(", ")}; pending: " \
                    "#{left.empty? ? "none" : left.join(", ")}"
            end
        end

        # `answer PATH O<n> --decision TEXT [--date] [--take N…]
        # [--replaces X<n>]`: the user's answer becomes a decision by user,
        # the question leaves Open, the X answers O edge is written (and X
        # replaces X with `--replaces`), the entries are taken: one event.
        # Without --take the user must have written since the question
        # was asked (Taking).
        class Answer < CLI::Command
            include Taking

            USAGE = "PATH ID"
            SYNOPSIS = "PATH O<n> --decision TEXT"
            SUMMARY = "file the user's answer as a decision by user; the " \
                      "question leaves Open"
            OPTIONS = {
                decision: ["--decision TEXT",
                           "the option chosen and every comment, quoted"],
                date: ["--date DATE", DATE]
            }.freeze
            REPLACES = /\AX[1-9]\d*\z/

            private

            def flags(parser)
                parser.on("--replaces X",
                          "X<n>, the decision it replaces") do |x|
                    @opts[:replaces] = x.strip
                end
                take_flag(parser)
                dry_run(parser)
            end

            def run(path, id)
                body = need(:decision).strip
                ids = takes
                result = write(path, own: id) do |change|
                    file(change, id, body, Address.parse(path), ids)
                end
                report(result, path, ids)
                0
            end

            def file(change, id, body, address, ids)
                question = open_question(change, id) or
                    refuse("#{id} is not asked under Open in #{address}")
                refuse("--decision is empty; quote the user") if body.empty?
                take(change, ids, asked: [:questions, question[:id]])
                ref = decision(change, id, body)
                change.update(:questions, question[:id], closed_at: Write.now)
                change.link("answers", ref, id)
                replaces(change, ref)
                ref
            end

            def open_question(change, id)
                return unless id.match?(/\AO[1-9]\d*\z/)

                journal.db[:questions].where(ledger_id: change.ledger_id,
                                             n: id[1..].to_i,
                                             closed_at: nil).first
            end

            def decision(change, id, body)
                body = "#{id}: #{body}" unless body.start_with?("#{id}:")
                date = @opts.fetch(:date) { Time.now.strftime("%F") }
                text = "- #{date} — #{body} — by user"
                refuse("not a decision line: #{text}") unless
                    Decide::LINE.match?(text)
                n = change.next_id("X")
                change.insert(:decisions, n:, date:, body:, by: "user",
                                          subject: id)
                "X#{n}"
            end

            def replaces(change, ref)
                old = @opts[:replaces] or return
                refuse("--replaces takes an X id, not #{old}") unless
                    REPLACES.match?(old)
                change.link("replaces", ref, old)
            end

            def report(result, path, ids)
                ref = result.value
                lines = [Render::Markdown.line(result.after, ref)]
                lines << take_line(result.after, ids) if ids.any? &&
                                                         !result.dry
                emit(result, path, first: ref, lines:)
            end
        end
    end
end
