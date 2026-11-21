# frozen_string_literal: true

require "json"
require "open3"

require_relative "../render/helper"
require "ledger/hooks/main"

# A hook test: the fixture ledger at /work/alpha (render/helper's
# builders), the hook run in-process on a payload naming that place, its
# answer parsed. Every test checks that the hook wrote nothing.
class HookTest < RenderTest
    PLACE = "/work/alpha"
    LAUNCHER = File.expand_path("../../../bin/ledger", __dir__)

    def teardown
        assert_equal @events_before, db[:events].count if @events_before
        super
    end

    # -> the Answer of hook NAME on PAYLOAD (a Hash), cwd the fixture's.
    def hook(name, **payload)
        @events_before = db[:events].count
        Ledger::Hooks.answer(name, JSON.generate({ cwd: PLACE, **payload }))
    end

    def json(answer) = JSON.parse(answer.out)

    def constraint(change, quote, where = "the user, turn 1")
        change.insert(:constraints, n: change.next_id("C"),
                                    text: "\"#{quote}\" — #{where}", quote:)
    end

    def entry(change, at: "2026-11-20 10:00:00", **fields)
        n = change.next_id("N")
        payload = JSON.generate({ id: "N#{n}", at:, **fields })
        change.insert(:inbox_entries, n:, at:, ref: fields[:ref], payload:)
    end

    # bin/ledger hook NAME run as a hook runs it, outside the bundle this
    # suite runs under: -> [stdout, stderr, status].
    def launch(name, payload, env = {})
        env = { "LEDGER_JOURNAL" => ENV.fetch("LEDGER_JOURNAL"), **env }
        Bundler.with_unbundled_env do
            Open3.capture3(env, "/bin/sh", LAUNCHER, "hook", name,
                           stdin_data: JSON.generate(payload))
        end
    end
end
