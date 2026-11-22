# frozen_string_literal: true

require "sequel"
require "stringio"

require "ledger"
require "ledger/cli"
require "ledger/commit_word"
require "ledger/hooks/edit_record"
require "ledger/hooks/head_record"
require "ledger/hooks/ledgers"

module Ledger
    module Hooks
        # PostToolUse on Bash: a command naming git after which the
        # repository's HEAD differs from the one this hook last saw for
        # that repository in this session (kept in `heads/SESSION_ID`
        # beside the journal file; the first sight only remembers) has
        # landed commits, old..new. They are attached with `piece
        # --commits` to the one piece of the project's live ledgers
        # whose commit word this session filed and that holds no commit
        # yet, else to the one piece awaiting commit; when no one piece
        # is meant, the session is told the commits to file. Nothing is
        # denied, and the hook is silent when HEAD did not move or no
        # live ledger is there.
        module CommitRecord
            GIT = /\bgit\b/

            Landing = Data.define(:ledger, :piece)

            module_function

            def call(payload)
                id = payload["session_id"].to_s
                return Answer.pass unless payload["tool_name"] == "Bash" &&
                                          EditRecord::BARE.match?(id) &&
                                          GIT.match?(command(payload))

                moved = HeadRecord.moved(id, payload["cwd"].to_s)
                moved.empty? ? Answer.pass : file(payload, id, moved)
            end

            def command(payload)
                input = payload["tool_input"]
                input.is_a?(Hash) ? input["command"].to_s : ""
            end

            # The answer for the COMMITS landed: attached to the piece
            # meant, or named to the session.
            def file(payload, id, commits)
                found = Ledgers.read(payload)
                return Answer.pass if found.empty?

                landing = meant(found, id)
                return say(unplaced(found.first, commits)) unless landing

                attach(landing, commits)
            end

            def say(text)
                Answer.json(hookSpecificOutput: {
                                hookEventName: "PostToolUse",
                                additionalContext: text
                            })
            end

            def unplaced(ledger, commits)
                "commits landed: #{commits.join(", ")}; file them with " \
                    "`bin/ledger piece #{ledger.address} P<n> --commits " \
                    "#{commits.join(",")}`"
            end

            def attach(landing, commits)
                piece = "P#{landing.piece[:n]}"
                argv = ["piece", landing.ledger.address, piece, "--commits",
                        commits.join(",")]
                code = CLI.run(argv, out: StringIO.new, err: StringIO.new)
                return say(unplaced(landing.ledger, commits)) unless code.zero?

                say("commits #{commits.join(", ")} recorded on #{piece}")
            end

            # The one piece a commit word of this session was filed on
            # and that holds no commit, else the one awaiting commit.
            def meant(found, id)
                hits = given_in(found, id)
                hits = awaiting_in(found) if hits.empty?
                hits.first if hits.one?
            end

            def given_in(found, id)
                pieces(found) { |ledger, piece| given?(ledger, piece, id) }
            end

            def awaiting_in(found)
                pieces(found) { |ledger, piece| awaiting?(ledger, piece) }
            end

            def pieces(found)
                found.flat_map do |ledger|
                    ledger.derive.pieces.filter_map do |piece|
                        Landing.new(ledger:, piece:) if yield(ledger, piece)
                    end
                end
            end

            def awaiting?(ledger, piece)
                ledger.derive.awaits(piece).any? { |word,| word == "commit" }
            end

            def given?(ledger, piece, id)
                return false if ledger.derive.commits(piece).any?

                links = CommitWord.links(ledger.snapshot, piece)
                actors(links.map { it[:event_id] }).include?("session:#{id}")
            end

            def actors(events)
                db = Sequel.sqlite(Journal.path, readonly: true)
                db[:events].where(id: events).select_map(:actor)
            ensure
                db&.disconnect
            end
        end
    end
end
