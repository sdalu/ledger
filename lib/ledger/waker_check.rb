# frozen_string_literal: true

require "open3"
require "sequel"

require "ledger/waker_check/outside"

module Ledger
    # `rake check:waker`: whether the waker can wake a session here, as
    # lines [state, name, detail] with state :ok or :warn, never :block
    # (the service starts without the waker). Every outside fact comes
    # in as an argument so a test hands its own: the journal path, the
    # process list, the version and settings checks.
    class WakerCheck
        # What bin/ledger-waker execs for a checkout, after its -I lib.
        LAUNCH = "-r ledger/waker/main"

        PS = lambda do
            out, _, status = Open3.capture3("ps", "-axww", "-o",
                                            "pid=,command=")
            status.success? ? out.lines.map(&:strip) : []
        rescue SystemCallError
            []
        end

        def initialize(root:, journal:, settings:, version: Version.new,
                       processes: PS)
            @root = root
            @journal = journal
            @settings = settings
            @version = version
            @processes = processes
        end

        def lines
            places = switched_on
            head = if places.nil? then [unreadable]
                   elsif places.empty?
                       [[:ok, "waker", "no ledger has the waker on"]]
                   else process + sessions(places)
                   end
            head + @version.lines + @settings.lines
        end

        private

        # The directories of live ledgers with the waker on; nil when the
        # journal cannot be read.
        def switched_on
            return nil unless File.exist?(@journal)

            read do |db|
                db[:ledgers].where(closed_at: nil, waker: true)
                            .select_map(:place)
                            .map { it.delete_suffix("/.claude") }.uniq.sort
            end
        end

        def read
            db = Sequel.sqlite(@journal, readonly: true)
            yield db
        rescue Sequel::Error
            @failure = "#{@journal} cannot be read"
            nil
        ensure
            db&.disconnect
        end

        def unreadable
            [:warn, "journal", @failure || "#{@journal} does not exist"]
        end

        def process
            found = @processes.call.find { ours?(it) }
            if found
                return [[:ok, "process", "bin/ledger-waker running, pid " \
                                         "#{found.split.first}"]]
            end

            [[:warn, "process", "no bin/ledger-waker of #{@root} is " \
                                "running; a ledger has the waker on"]]
        end

        def ours?(line)
            line.include?("-I #{File.join(@root, "lib")} #{LAUNCH}")
        end

        def sessions(places)
            read { |db| recorded(db, places) + unrecorded(db) } ||
                [unreadable]
        end

        def recorded(db, places)
            places.map do |dir|
                if db[:sessions].where(cwd: dir).empty?
                    [:warn, "sessions", "none recorded in #{dir}: restart " \
                                        "its sessions so session-start runs"]
                else
                    [:ok, "sessions", "recorded in #{dir}"]
                end
            end
        end

        # session_stops carries no directory, so the newest turn end of
        # any session is the one tested: with no sessions row the waker
        # cannot find that session (the one after /clear).
        def unrecorded(db)
            id = db[:session_stops].order(Sequel.desc(:at)).get(:session_id)
            return [] if id.nil? || db[:sessions].where(session_id: id).any?

            [[:warn, "session", "the newest turn end is session #{id}, " \
                                "which has no sessions row"]]
        end
    end
end
