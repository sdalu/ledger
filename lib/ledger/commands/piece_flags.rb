# frozen_string_literal: true

module Ledger
    module Commands
        # The piece command's switches that are not a plain --FIELD VALUE:
        # spelled against OptionParser's habits, or taking a file, or none.
        module PieceFlags
            private

            def special_flags(parser)
                no_picture_flag(parser)
                announce_flag(parser)
                handback_flag(parser)
                no_commit_flag(parser)
                irreversible_flag(parser)
                parser.on("--claim", "take over an out piece's claim for " \
                                     "this session; the status stays") do
                    @opts["claim"] = true
                end
            end

            # Spelled "--no-picture WHY", OptionParser would read the
            # negation of a --picture switch and leave WHY behind.
            def no_picture_flag(parser)
                parser.on("--no-picture", "=WHY", String,
                          "why the piece needs no before/after") do |why|
                    @opts["no-picture"] = why
                end
            end

            # Spelled "--no-commit WHY", for the reason --no-picture is.
            def no_commit_flag(parser)
                # The pattern, not String: String refuses the empty WHY.
                parser.on("--no-commit", "=WHY", /\A.*\z/m,
                          "why the piece's work stays uncommitted; " \
                          "'' clears it") do |why|
                    @opts["no-commit"] = why
                end
            end

            # Whether the piece's step cannot be taken back: 3 more on the
            # step risk of each word it awaits.
            def irreversible_flag(parser)
                said = "its step cannot be taken back: the step risk +3"
                parser.on("--[no-]irreversible", said) do |set|
                    @opts["irreversible"] = set
                end
            end

            def handback_flag(parser)
                parser.on("--handback", "with --status back alone: a " \
                                        "delegate's hand-back; a piece out " \
                                        "goes back, any other stays") do
                    @opts["handback"] = true
                end
            end

            def announce_flag(parser)
                parser.on("--announce FILE",
                          "a dispatch's ANNOUNCE block, from FILE or - " \
                          "for stdin") do |file|
                    @opts["announce"] = file
                end
            end
        end
    end
end
