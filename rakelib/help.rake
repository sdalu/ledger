# frozen_string_literal: true

# help.rake -- what `rake help` prints.
#
# `rake -T` already lists the tasks, so this earns its place by doing
# what -T cannot: grouping them by when they are wanted, showing the
# environment variables that change what a task does (arguments, not
# tasks, and so invisible to -T), and carrying the two facts about
# running a service here that get looked up every time -- that nothing
# supervises it, and that USR2 restarts it in place.
#
# It ends by listing any described task it does not already mention,
# so a project that adds one gets it in the help without editing this
# file: a curated help text that silently goes stale is worse than
# none.
#
# THAT LAST PART NEEDS ONE LINE IN THE Rakefile, before anything else:
#
#     Rake::TaskManager.record_task_metadata = true
#
# Rake attaches a `desc` to its task only when it already intends to
# print one -- see the guard in task_manager.rb's define_task -- so
# during an ordinary run every task's comment is nil and this file can
# see nothing. The Rakefile is loaded before rakelib, which is why the
# line goes there and not here.

module Help
    # The service's own name, for the first line. Taken from the
    # umbrella rather than written down, for the usual reason.
    def self.service
        File.basename(Dir["lib/*.rb"].first || Dir.pwd, ".rb")
    end

    def self.paint(text, colour)
        defined?(Preflight) ? Preflight.paint(text, colour) : text
    end

    # The tasks the text below describes. Anything else carrying a
    # description is listed under "Also".
    DESCRIBED = %w[default test rubocop clean help
                   server:start server:stop server:restart server:status
                   check check:pre-flight].freeze

    def self.extra
        Rake.application.tasks.select do |task|
            task.comment && !DESCRIBED.include?(task.name)
        end
    end

    def self.tasks
        <<~TEXT
            #{paint(service, :bold)} — a Ruby web service.

              #{paint("Gate", :bold)}
                rake                      the suite, then the style check
                rake test                 the suite alone
                rake rubocop              the style check alone

              #{paint("Running", :bold)}
                rake server:start         serve it, in the foreground
                  DEBUG=1                 to be edited: real errors, request
                                          logging, templates reloaded, and a
                                          throwaway store
                  PRODUCTION=1            to be used: templates cached, the
                                          environment named rather than left
                                          to an unset variable
                  TMUX=name               detached, in a named tmux session
                                          (SCREEN=name for screen); attach to
                                          watch it, stop as usual
                rake server:stop          ask it to stop, and wait for it
                rake server:restart       re-exec in place, keeping the
                                          listening sockets; starts it
                                          if it is not running

              #{paint("Inspecting", :bold)}
                rake check                every check:* there is
                rake check:pre-flight     gems, config, tools, addresses
                rake server:status        is it running, and with what
                                          settings?

              #{paint("Housekeeping", :bold)}
                rake clean                remove what a run wrote
                rake help                 this message

        TEXT
    end

    def self.notes
        <<~TEXT
            Nothing supervises the service: it runs in the foreground, and a
            change to ruby reaches it when you restart it yourself. Templates
            and public/ are re-read per request and need no restart.
            `kill -USR2 <pid>` restarts in place, keeping the listening
            sockets, so there is no window where the address is still taken;
            puma prints its pid at startup.

            `rake -T` lists every task, including any this message does not.
        TEXT
    end
end

desc "This message"
task :help do
    puts Help.tasks
    unless Help.extra.empty?
        puts "  #{Help.paint("Also", :bold)}"
        # Padded to the same column the curated lines use, so an
        # added task does not look like a different kind of thing.
        Help.extra.each do |task|
            puts "    #{"rake #{task.name}".ljust(26)}#{task.comment}"
        end
        puts
    end
    puts Help.notes
end
