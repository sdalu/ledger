# frozen_string_literal: true

require_relative "py_json"
require_relative "render/text"

module LedgerViewer
    # What is sent to a ledger: one JSON line each, appended to
    # PATH.inbox, which the session files and nobody else writes to. The
    # next number and the append are one step under a lock, so two sends
    # never take the same id.
    module Inbox
        LOCK = Mutex.new
        STAMP = "%Y-%m-%d %H:%M:%S"

        # Appends one line for each of `bodies` (the fields between the
        # time and the text, in order) and returns the ids given.
        def self.append(path, bodies, now: Time.now)
            LOCK.synchronize do
                first = count(path) + 1
                ids = bodies.each_index.map { "N#{first + it}" }
                lines = bodies.zip(ids).map { line(*it, now) }
                File.open("#{path}.inbox", "a", encoding: "UTF-8") do |file|
                    file.write(lines.join)
                end
                ids
            end
        end

        def self.line(body, id, now)
            fields = { "id" => id, "at" => now.strftime(STAMP) }
                     .merge(body.fields).merge("text" => body.text)
            "#{PyJson.dump(fields)}\n"
        end

        # The entries the engine counts in the file: its non-blank lines,
        # cut at newlines only (a note may hold U+2028 inside its one
        # JSON line).
        def self.count(path)
            text = File.read("#{path}.inbox", encoding: "UTF-8").scrub("�")
            text.split("\n", -1)
                .count { !Render::Text.strip(it).empty? }
        rescue SystemCallError
            0
        end
    end
end
