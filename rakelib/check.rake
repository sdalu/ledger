# frozen_string_literal: true

# check.rake -- can this start? Needs preflight.rake beside it.
#
# `rake check` runs every check:* task there is, resolved when it
# runs rather than when it loads, so a project adding its own
# check:certificates in another rakelib file gets it included without
# editing anything here. That is the point of the namespace: the
# generic rule applies whatever sub-rules exist.
#
# Separate from the server tasks because it wants a different exit
# code. A pre-flight must fail loudly when the service cannot start;
# "nothing is running" is an answer rather than an error.

namespace :check do
    desc "Gems, configuration, external tools, addresses"
    task :"pre-flight" do
        # The report goes to stdout and the verdict to stderr; without
        # this the verdict overtakes the lines it is about.
        $stdout.sync = true
        Preflight.heading("Pre-flight")

        Preflight.title("Dependencies")
        blocking = Preflight.gems

        Preflight.title("Configuration")
        blocking += Preflight.files
        config, failed = Preflight.settings
        blocking += failed

        unless Preflight::TOOLS.empty?
            Preflight.title("External tools")
            blocking += Preflight.tools
        end

        if config.respond_to?(:bind)
            Preflight.title("Addresses")
            blocking += Preflight.addresses(config)
        end

        abort("\n#{blocking} blocking problem(s); it will not start.") if
            blocking.positive?

        if Preflight.busy.positive?
            puts "\nNothing is misconfigured, but an address is already " \
                 "in use.\nStop that instance, or restart it in place: " \
                 "rake server:restart."
        else
            puts "\nReady to start."
        end
    end
end

desc "Run every check:* task"
task :check do
    # Resolved now rather than at load time: rakelib files load in
    # name order, so a check:* defined in a later file would be
    # invisible to a dependency list written here.
    subtasks = Rake.application.tasks
                   .select { it.name.start_with?("check:") }
    abort("no check:* tasks are defined.") if subtasks.empty?

    subtasks.each(&:invoke)
end
