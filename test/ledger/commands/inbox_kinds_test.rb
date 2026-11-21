# frozen_string_literal: true

require_relative "helper"

# `inbox`: the head line of an entry names its kind, a comment on a
# question told from an answer to it.
class InboxKindsTest < CommandCase
    def send_entry(text, **fields)
        Ledger::Inbox.append(@journal, BETA, [{ "text" => text, **fields }],
                             actor: "cli", now: Time.new(2026, 11, 21, 8, 0, 0))
    end

    def test_a_comment_on_a_question_is_no_answer
        send_entry("which file?", ref: "O1", comment: true)
        send_entry("warm", ref: "O1")
        assert_equal "N1 (2026-11-21 08:00:00, comment on question O1, " \
                     "not an answer):\n    which file?\n" \
                     "N2 (2026-11-21 08:00:00, answer to O1):\n    warm\n",
                     ok("inbox", BETA)
    end
end
