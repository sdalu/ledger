# frozen_string_literal: true

module Ledger
    module Render
        class Json
            # A piece's route: `route`, {model, effort, skills, peer} or
            # null, and `route_text` as the piece line writes it.
            module Route
                module_function

                def call(piece)
                    { route: route(piece), route_text: text(piece) }
                end

                def route(piece)
                    return unless piece[:peer] || piece[:model]

                    { model: piece[:model], effort: piece[:effort],
                      skills: piece[:skills], peer: piece[:peer] }
                end

                def text(piece)
                    return "peer: #{piece[:peer]}" if piece[:peer]
                    return unless piece[:model]

                    skills = ", skills: #{piece[:skills]}" if piece[:skills]
                    "#{piece[:model]}, effort: #{piece[:effort]}#{skills}"
                end
            end
        end
    end
end
