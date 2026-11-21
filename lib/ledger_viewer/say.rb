# frozen_string_literal: true

require_relative "refusal"
require_relative "render/reading"
require_relative "render/text"
require_relative "say_all"
require_relative "say_answer"
require_relative "say_ledger"
require_relative "say_picture"
require_relative "say_tray"
require_relative "say_word"

module LedgerViewer
    # What a posted form says, checked against the ledger's JSON v1
    # document, by the rules of a post: the entries
    # to append, or the Refusal that names why nothing is. SayAll is its
    # say-all, SayTray an item of the tray.
    class Say
        include SayAll
        include SayAnswer
        include SayLedger
        include SayPicture
        include SayTray
        include SayWord

        MAX_TEXT = 4000
        # What a send is: the fields between the time and the text, the
        # text, and the card the page goes back to.
        Body = Data.define(:fields, :text, :anchor)
        KINDS = { /\AO\p{Nd}+\z/ => :answer,
                  /\AP\p{Nd}+\z/ => :comment }.freeze
        FILLED = %w[choice notes order picks word].freeze

        def initialize(data, form)
            @data = data
            @reading = Render::Reading.new(data)
            @form = form
            @text = clean(form["text"])
            @planned = pieces.select { it["status"] == "planned" }
                             .map { it["id"] }
        end

        # The one entry the form makes, as a one-element list.
        def one
            ref = @form["ref"]
            ref = nil if ref.empty?
            fields = { "ref" => ref }
            kind = kind_of(ref)
            check(kind, ref, fields)
            nothing! unless ledger_word?(kind) || something?(fields)
            too_long!(fields)
            [Body.new(fields:, text: @text, anchor: anchor(kind, ref))]
        end

        private

        def check(kind, ref, fields)
            case kind
            when :answer then answer(ref, fields)
            when :word then word(ref, fields)
            when :comment, :picture then aside(kind, ref, fields)
            when :order then order(fields)
            when *SayLedger::WORDS then ledger_word(kind)
            when :unknown then refuse(400, "Unknown kind of entry.")
            end
        end

        # What answers nothing on a card: a comment, a picture asked.
        def aside(kind, ref, fields)
            kind == :picture ? picture(ref, fields) : comment(ref)
        end

        def kind_of(ref)
            kind = base_kind(ref)
            return :picture if %i[answer comment].include?(kind) &&
                               picture?(ref)

            kind == :comment && !@form["word"].empty? ? :word : kind
        end

        def base_kind(ref)
            return :note if ref.nil?
            return :order if ref == "order"
            return ref.to_sym if %w[close abandon].include?(ref)

            KINDS.find { |rx, _| rx.match?(ref) }&.last || :unknown
        end

        # A planned piece takes a comment before it goes out; one
        # awaiting the user's word takes one too, to ask before giving it.
        def comment(ref)
            return if @planned.include?(ref) || !words_of(piece(ref)).empty?

            refuse(409, "#{ref} is neither planned nor awaiting your " \
                        "word; send it as a note.")
        end

        def order(fields)
            proposed = @form["order"].split(LIST).reject(&:empty?)
            unless @planned.length >= 2 && proposed.sort == @planned.sort
                refuse(400, "The order must name each planned piece once: " \
                            "#{@planned.join(", ")}.")
            end
            waits!(proposed)
            fields["order"] = proposed
        end

        def waits!(proposed)
            after = pieces.to_h { [it["id"], it["after"]] }
            proposed.each_with_index do |ref, at|
                late = after.fetch(ref, []) & proposed.drop(at + 1)
                next if late.empty?

                refuse(400, "#{ref} waits for #{late.join(", ")}: " \
                            "put it after.")
            end
        end

        def something?(fields)
            return true unless @text.empty?

            FILLED.any? { fields[it] && !fields[it].empty? }
        end

        def nothing! = refuse(400, "Nothing to send.")

        def too_long!(fields)
            notes = fields.fetch("notes", {}).values
            return unless @text.length > MAX_TEXT ||
                          notes.any? { it.length > MAX_TEXT }

            refuse(400, "Keep each box under #{MAX_TEXT} characters.")
        end

        # Where the page goes back to: the card acted on.
        def anchor(kind, ref)
            return "inbox" if %i[note order].include?(kind)
            return kind.to_s if ledger_word?(kind)
            return "q-#{ref}" if ref.start_with?("O")

            words_of(piece(ref)).empty? ? "piece-#{ref}" : "p-#{ref}"
        end

        def pieces = @data["pieces"]
        def piece(ref) = pieces.find { it["id"] == ref }
        def words_of(piece) = piece ? piece["awaits"].map { it["word"] } : []
        def refuse(status, why) = raise(Refusal.new(status, why))
        def clean(text) = Render::Text.strip(text.gsub("\r\n", "\n"))
    end
end
