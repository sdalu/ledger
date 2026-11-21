# frozen_string_literal: true

require "date"

require_relative "text"

module LedgerViewer
    module Render
        # The decisions dated today that answer a question: what the
        # page lists under Waiting on you as answered.
        module Answered
            DECISION = /\A- (\d{4}-\d{2}-\d{2}) — (O\d+): (.*)\z/
            QUOTED = /\A"((?:[^"\\]|\\.)*)"/
            CODE = /\A(\S{1,3}): (.+)\z/
            # One decision: the index of its line, the question, the
            # title it quotes, the letter it chose.
            Line = Data.define(:at, :id, :title, :letter)

            module_function

            def of(decisions, today: Date.today.iso8601)
                decisions.each_with_index.filter_map do |line, at|
                    found = DECISION.match(line)
                    line(found, at) if found && found[1] == today
                end
            end

            def line(found, at)
                letter, title = quoted(found[3])
                title = found[2] if title.empty?
                Line.new(at:, id: found[2], title:,
                         letter: letter.length <= 3 ? letter : "")
            end

            # [the choice's letter, the title] of what the decision quotes;
            # one that quotes nothing gives its own words.
            def quoted(text)
                quote = QUOTED.match(text)
                return own_words(text) unless quote

                said = quote[1].gsub('\\"', '"')
                letter, sep, rest = said.partition(" = ")
                letter = "" if sep.empty?
                rest = said if sep.empty?
                [Text.strip(letter), Text.strip(rest.split(" — ", 2).first)]
            end

            # The decision in its own words, up to who decided or a note;
            # a short leading code (R1) is its choice.
            def own_words(text)
                words = Text.strip(text.split(" — ", 2).first)
                code = CODE.match(words)
                letter, rest = code ? [code[1], code[2]] : ["", words]
                [Text.strip(letter), Text.strip(rest.split(" — ", 2).first)]
            end
        end
    end
end
