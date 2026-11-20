# frozen_string_literal: true

# server.rake -- start, stop, restart and status. Needs preflight.rake
# beside it, for the pidfile and the launcher.
#
# `rake server` is an alias for `server:start`, because that is what
# anyone types first and there is no reason to make them learn the
# namespace before they can run the thing. `rake status` likewise
# reaches server:status.
#
# start runs in the FOREGROUND, under whoever typed it: nothing here
# daemonises and nothing supervises. stop and restart are for the
# other terminal, which is why they need the pidfile -- guessing at a
# process from its command line is how the wrong server gets killed on
# a machine running two of them.
#
# START AND STOP ARE IDEMPOTENT: asking for a state the service is
# already in reports that and succeeds. This is what lets either go in
# a script without a test around it, and it is the difference between
# "start it" and "start it if it is not already started", which nobody
# should have to write. The one case start refuses is the one where
# the wanted state cannot be reached: an address held by something
# that is not this service.
#
# SCREEN=name OR TMUX=name STARTS IT DETACHED, in a named screen or tmux
# session, so it outlives the terminal that started it and anyone can
# attach to watch it. That is a terminal, not a supervisor: when the
# service exits the session closes, and nothing starts it again. stop
# and restart work through the pidfile exactly as for a foreground run.
# tmux sets TMUX itself in every pane, to its socket ("/tmp/tmux-1000/
# default,1234,0"), so only a plain name counts as a request; and the
# variable is dropped before tmux runs, since tmux reads it to find its
# server.
#
# RESTART STARTS A STOPPED SERVICE, as `service restart` does
# everywhere else. Refusing would be defensible -- a pidfile cannot
# tell a service stopped on purpose from one that died -- but it
# would also be a local rule that nobody expects, and the surprise
# costs more than the case it guards.

# Starting the launcher inside a named screen or tmux session.
module Detached
    module_function

    NAME = /\A[A-Za-z0-9_-]+\z/

    # [:screen or :tmux, name], or nil for a foreground start.
    def requested
        screen = ENV.fetch("SCREEN", nil)
        tmux = asked_tmux
        abort("SCREEN= and TMUX= both given; pick one.") if screen && tmux
        return nil unless screen || tmux

        [screen ? :screen : :tmux, valid(screen || tmux)]
    end

    # tmux's own TMUX is its socket, "path,pid,index": not a request.
    def asked_tmux
        tmux = ENV.fetch("TMUX", nil)
        tmux unless tmux.nil? || tmux.include?(",")
    end

    def valid(name)
        return name if name.match?(NAME)

        abort("session name #{name.inspect}: letters, digits, - and _ only.")
    end

    def start(tool, name, launcher)
        system("command -v #{tool} >/dev/null 2>&1") or
            abort("#{tool} is not installed; drop #{tool.upcase}= to run " \
                  "in the foreground.")
        taken?(tool, name) and
            abort("a #{tool} session named #{name} already exists and the " \
                  "service is not running in it; pick another name, or " \
                  "end that session.")
        launch(tool, name, launcher) or
            abort("#{tool} could not start the session.")
        report(tool, name)
    end

    def taken?(tool, name)
        if tool == :tmux
            system(child_env, "tmux", "has-session", "-t", "=#{name}",
                   err: File::NULL)
        else
            `screen -ls 2>/dev/null`.match?(/^\s*\d+\.#{name}\s/)
        end
    end

    # A running tmux server builds a new session's environment from its
    # own, not from this process's: DEBUG=1 or PRODUCTION=1 would be lost.
    # So the launcher runs under env with this process's environment,
    # less the session request itself.
    def launch(tool, name, launcher)
        root = File.expand_path("..", __dir__)
        kept = ENV.to_h.except(*DROP).map { |k, v| "#{k}=#{v}" }
        cmd = ["env", *DROP.flat_map { ["-u", it] }, *kept, launcher]
        if tool == :tmux
            system(child_env, "tmux", "new-session", "-d", "-s", name,
                   "-c", root, *cmd)
        else
            system(child_env, "screen", "-dmS", name, *cmd, chdir: root)
        end
    end

    # Unset, not merely left out: system(env, ...) merges its hash into
    # the environment, and a TMUX=name left in it is read by tmux as the
    # path of its socket -- a socket file named after the session,
    # created in the project (seen, 2026-11-11).
    DROP = %w[TMUX SCREEN STY].freeze

    def child_env
        DROP.to_h { [it, nil] }
    end

    # The pidfile is the proof it started; the session is where to look
    # when it did not.
    def report(tool, name)
        attach = tool == :tmux ? "tmux attach -t #{name}" : "screen -r #{name}"
        40.times { Preflight.running_pid ? break : sleep(0.25) }
        pid = Preflight.running_pid
        unless pid
            abort("no pid in #{Preflight::PIDFILE} after 10s; " \
                  "`#{attach}` to see why.")
        end
        puts "started in #{tool} session #{name} (pid #{pid}); " \
             "`#{attach}` to watch."
    end
end

namespace :server do
    desc "Serve it (DEBUG=1 to edit, PRODUCTION=1 to use; SCREEN=name or " \
         "TMUX=name to detach it)"
    task :start do
        # Refused here as well as in the launcher and the library. A
        # check that lives in one entry point is one the others obey
        # silently, and this is the entry point most people use.
        if ENV["DEBUG"] == "1" && ENV["PRODUCTION"] == "1"
            abort("PRODUCTION=1 and DEBUG=1 contradict each other; " \
                  "pick one: DEBUG to edit, PRODUCTION to serve.")
        end

        pid = Preflight.running_pid
        if pid
            puts "already running (pid #{pid})."
            next
        end

        # No pid of ours, but the address is taken: the wanted state
        # is unreachable and saying so beats letting puma report it as
        # a backtrace. Not idempotent, and correctly not -- running
        # this again will not fix it.
        taken = Preflight.taken_addresses
        unless taken.empty?
            abort("#{taken.join(", ")} already in use by something that " \
                  "is not this service (no live pid in " \
                  "#{Preflight::PIDFILE}). Free it, or stop that process.")
        end

        launcher = Preflight.launcher or
            abort("no launcher found: expected one executable in bin/, " \
                  "or ./run")
        if (how = Detached.requested)
            Detached.start(*how, File.expand_path(launcher, "#{__dir__}/.."))
            next
        end
        # exec, not sh: rake has nothing left to do once the launcher
        # is running, and a rake still wrapping it turns a clean stop
        # from the other terminal into "rake aborted!" in this one.
        exec File.expand_path(launcher, "#{__dir__}/..")
    end

    desc "Stop it"
    task :stop do
        pid = Preflight.running_pid
        unless pid
            # A pidfile outlives the process it named; clearing a
            # stale one here is what makes a second stop as quiet as
            # the first.
            Preflight.clear_stale_pidfile
            puts "not running."
            next
        end

        begin
            Process.kill("TERM", pid)
        rescue Errno::EPERM
            abort("pid #{pid} is not ours to signal.")
        end
        # TERM is a request. Waiting and reporting what happened beats
        # a task that returns at once and leaves the caller to find
        # out for themselves whether it worked.
        # The wait outlasts puma's own drain (force_shutdown_after), or
        # a request that hangs makes stop report a failure puma is
        # about to resolve by itself.
        wait = Preflight.stop_wait
        (wait * 4).times { Preflight.running_pid ? sleep(0.25) : break }
        if Preflight.running_pid
            abort("pid #{pid} is still up #{wait}s after TERM; it may " \
                  "be finishing a job. Signal it again, or KILL it by " \
                  "hand.")
        end
        puts "stopped (was pid #{pid})."
    end

    desc "Restart it, or start it if it is not running"
    task :restart do
        pid = Preflight.running_pid
        unless pid
            # What `service restart` does everywhere else, so it is
            # what anyone typing this expects. Note the asymmetry it
            # brings, which is why it is announced: restarting a
            # RUNNING service returns at once, because USR2 is a
            # signal, while starting a stopped one hands over to the
            # foreground start and blocks until it is stopped again.
            puts "not running; starting it (this will not return)."
            Rake::Task["server:start"].invoke
            next
        end

        # USR2 makes puma re-exec itself. The pid does NOT change --
        # the process image is replaced under it -- and the listening
        # sockets are kept, so there is no window where the address is
        # taken and a new process cannot bind.
        Process.kill("USR2", pid)
        sleep 2
        unless Preflight.running_pid == pid
            abort("pid #{pid} did not survive USR2; check the log. A " \
                  "syntax error means the re-exec'd process exited and " \
                  "the old one is already gone.")
        end
        puts "restarted in place (pid #{pid} kept its sockets)."
    end

    desc "Is it running, and with what settings?"
    task :status do
        $stdout.sync = true
        config, failed = Preflight.settings(quiet: true)
        abort("settings would not load; run `rake check`.") if
            failed.positive? || config.nil?

        Preflight.heading("Status")
        Preflight.title("Process")
        pid = Preflight.running_pid
        if pid
            Preflight.item(:ok, "pid", "#{pid} (#{Preflight::PIDFILE})")
        else
            Preflight.item(:info, "pid", "no live pid recorded")
        end

        Preflight.title("Listening")
        Preflight.listening(config)

        Preflight.title("Settings")
        Preflight.settings_report(config)
        puts
    end
end

desc "Alias for server:start"
task server: "server:start"

desc "Alias for server:status"
task status: "server:status"
