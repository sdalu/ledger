# frozen_string_literal: true

require "fileutils"
require "open3"
require "sequel"

require "ledger"
require "ledger/commit_word"
require "ledger/text/awaits"

module Ledger
    module Hooks
        # The user's push word, read from the same `word` decisions as
        # CommitWord (a decision by user, body `P<n>: "WORDS"`, WORDS
        # naming push, with a led_to edge to the piece). A push word is
        # unspent while it is newer than the last push the word-gate hook
        # let through for the repository, kept in `pushes` beside the
        # journal file, one `TOP<TAB>MILLISECONDS` line per repository.
        module PushWord
            module_function

            # Whether a push word was filed on a piece of FOUND after the
            # last allowed push of the repository TOP.
            def unspent?(found, top)
                since = pushed(top)
                filed(found).any? { it > since }
            end

            # The times (ms) the push word was filed on pieces of FOUND.
            def filed(found)
                events = found.flat_map do |ledger|
                    ledger.derive.pieces.flat_map do |piece|
                        links(ledger.snapshot, piece).map { it[:event_id] }
                    end
                end
                times(events)
            end

            def links(snapshot, piece)
                snapshot.links.select do |link|
                    link[:kind] == "led_to" && link[:to_kind] == "P" &&
                        link[:to_row] == piece[:id] &&
                        push?(CommitWord.decision(snapshot, link[:from_row]))
                end
            end

            def push?(row)
                return false unless row && row[:by] == "user"

                words = CommitWord::BODY.match(row[:body])&.[](:words).to_s
                Text::Awaits.split(words).map(&:strip).include?("push")
            end

            def times(events)
                db = Sequel.sqlite(Journal.path, readonly: true)
                db[:events].where(id: events).select_map(:at)
            ensure
                db&.disconnect
            end

            # The top of the repository at DIR, DIR itself when git does
            # not tell.
            def top(dir)
                out, _, status = Open3.capture3("git", "-C", dir,
                                                "rev-parse", "--show-toplevel")
                status.success? ? out.chomp : dir
            rescue SystemCallError
                dir
            end

            # The time (ms) of the last allowed push of TOP, 0 for none.
            def pushed(top) = heads.fetch(top, "0").to_i

            def heads
                return {} unless File.file?(memory)

                File.readlines(memory, chomp: true).to_h { it.split("\t", 2) }
            end

            def memory = File.join(File.dirname(Journal.path), "pushes")

            # Remembers a push allowed now for TOP, written to a temp path
            # and renamed: an interrupt leaves the old record or the new.
            def record(top)
                FileUtils.mkdir_p(File.dirname(memory))
                lines = heads.merge(top => Write.now.to_s).map do |key, time|
                    "#{key}\t#{time}\n"
                end
                tmp = "#{memory}.#{Process.pid}"
                File.write(tmp, lines.join)
                File.rename(tmp, memory)
                nil
            end
        end
    end
end
