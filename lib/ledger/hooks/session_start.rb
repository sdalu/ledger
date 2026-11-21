# frozen_string_literal: true

require "ledger/hooks/inbox"
require "ledger/hooks/resume_view"

module Ledger
    module Hooks
        # SessionStart: entries the user wrote in the viewer while no
        # session ran are shown with the filing steps, whatever the
        # source; on startup, resume and compact the resume view follows,
        # its budget apart from the entries (the user's words are never
        # cut). Nothing to show: no output.
        module SessionStart
            SOURCES = %w[startup resume compact].freeze
            INTRO = "Entries are waiting in the ledger viewer's inbox, " \
                    "written before this session began."

            module_function

            def call(payload)
                found = Ledgers.read(payload)
                view = ResumeView.render(found) if
                    SOURCES.include?(payload["source"])
                text = [entries(found), view].compact
                return Answer.pass if text.empty?
                Answer.json(hookSpecificOutput: {
                                hookEventName: "SessionStart",
                                additionalContext: text.join("\n\n")
                            })
            end

            def entries(found)
                parts = Inbox.parts(found)
                return if parts.empty?
                steps = Inbox::STEPS.sub("before you stop",
                                         "before anything else")
                [INTRO, steps, *parts].join("\n")
            end
        end
    end
end
