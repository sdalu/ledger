# frozen_string_literal: true

require_relative "helper"

# U12, the claim: `out` needs a session and holds the piece for it.
class ClaimTest < JournalTest
    def setup
        super
        @piece = write { piece(it) }.value
    end

    def test_out_without_a_session_is_refused
        assert_raises(Ledger::Refused) { write { it.status(@piece, "out") } }
        assert_equal "planned", db[:pieces].get(:status)
    end

    def test_out_stores_the_session
        write { it.status(@piece, "out", session: "one") }

        assert_equal({ status: "out", claimed_by: "one" },
                     db[:pieces].first.slice(:status, :claimed_by))
    end

    def test_a_second_session_is_refused_naming_the_holder_and_the_time
        at = Time.new(2026, 11, 20, 10, 30, 0).to_i * 1000
        write(at:) { it.status(@piece, "out", session: "one") }
        error = assert_raises(Ledger::Claimed) do
            write { it.status(@piece, "out", session: "two") }
        end

        assert_equal "P1 is out under one since 2026-11-20 10:30:00",
                     error.message
        assert_equal "one", db[:pieces].get(:claimed_by)
    end

    def test_the_holder_may_say_out_again
        write { it.status(@piece, "out", session: "one") }
        write { it.status(@piece, "out", session: "one") }

        assert_equal "one", db[:pieces].get(:claimed_by)
    end

    def test_any_other_status_clears_the_claim
        write { it.status(@piece, "out", session: "one") }
        write { it.status(@piece, "back") }

        assert_equal({ status: "back", claimed_by: nil },
                     db[:pieces].first.slice(:status, :claimed_by))
    end

    def test_another_session_takes_over_through_planned
        write { it.status(@piece, "out", session: "one") }
        write { it.status(@piece, "planned") }
        write { it.status(@piece, "out", session: "two") }

        assert_equal "two", db[:pieces].get(:claimed_by)
    end

    def test_the_schema_keeps_a_claim_to_an_out_piece
        assert_raises(Sequel::CheckConstraintViolation) do
            db[:pieces].where(id: @piece).update(claimed_by: "one")
        end
    end
end
