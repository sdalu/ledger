# frozen_string_literal: true

module LedgerViewer
    module Render
        # The part of a question's card that a piece building it adds
        # (piece --builds): under the picker, the piece's title, its
        # plan, its risk and its pictures, so one card asks the answer
        # and the start together, its one button sending both.
        class BuildsPart
            def initialize(kit)
                @kit = kit
                @scope = kit.scope
            end

            # SPEC (a SayForm::Spec) with the piece building its question
            # while no answer is sent; SPEC itself otherwise.
            def spec(spec)
                piece = spec.replaces.empty? && @kit.reading.builder(spec.ref)
                return spec unless piece

                spec.with(starts: piece["id"], built: html(piece))
            end

            def html(piece)
                id = piece["id"]
                "<div class=\"builds-part\" id=\"builds-#{id}\">" \
                    "#{head(id, piece["title"])}#{facets(piece)}" \
                    "#{@kit.mockups.sides(piece)}</div>"
            end

            private

            def head(id, title)
                "<p class=\"builds-head\">Then starts <a class=\"id-link\" " \
                    "href=\"#piece-#{id}\">#{@scope.chip(id)}</a> " \
                    "#{@scope.inline(title)}</p>"
            end

            def facets(piece)
                @kit.ties.piece(piece) + @kit.cases.facets(piece) +
                    @kit.raid.piece(piece)
            end
        end
    end
end
