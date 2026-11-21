# frozen_string_literal: true

# preflight.rake -- what `rake check` and `rake status` both need.
#
# Drop this and its two companions in rakelib/; rake loads
# rakelib/*.rake by itself, so the Rakefile needs no edit. The module
# is its own file because both tasks read the same settings and print
# the same shaped lines, and two copies of that would drift into two
# answers about one service.
#
# ONE THING TO SET: TOOLS, below. Everything else is found rather than
# configured, because a template carrying one project's names is a
# template that silently checks the wrong project.
#
# Colour comes from pastel when it is in the bundle and is skipped
# when it is not, so this runs anywhere. pastel already writes plain
# text when stdout is not a terminal, which is what makes the output
# safe to pipe.

require "fileutils"
require "shellwords"
require "socket"

module Preflight
    # The external commands this service shells out to, and what stops
    # working without each. Only a project knows these, so this is the
    # list to fill in; an empty list skips the section entirely.
    #
    #   TOOLS = { "pdftotext" => "reading PDFs" }.freeze
    TOOLS = {}.freeze

    INK = begin
        require "pastel"
        Pastel.new
    rescue LoadError
        nil
    end

    # The verdict words and their colours. BLOCK is upper-case so it
    # still stands out in a pipe, where the colour is gone, and "--"
    # is a fact rather than a verdict: `status` reports a machine
    # rather than judging it, and a stopped service is an answer.
    STATES = { ok: ["ok", :green], info: ["--", :dim],
               warn: ["warn", :yellow], block: ["BLOCK", :red] }.freeze

    # Ports found busy during a pre-flight, so the closing line can
    # tell "nothing is wrong" apart from "something is already there",
    # which are opposite instructions to whoever is reading.
    @busy = 0

    class << self
        attr_accessor :busy
    end

    module_function

    def paint(text, colour) = INK ? INK.decorate(text, colour) : text

    def heading(text)
        puts "\n#{paint(text, :bold)}"
    end

    # A column of verdicts with nothing above it is a column of noise:
    # every item belongs under a title saying what is being judged.
    def title(text)
        puts "\n  #{paint(text, :bold)}"
    end

    # Returns what this line contributes to the blocking count, so the
    # report and the exit status cannot disagree about what failed.
    # Padded BEFORE colouring: a coloured string carries escape bytes
    # that printf counts and a terminal does not, so padding after
    # would align the output only when colour happened to be off.
    def item(state, name, detail = nil)
        label, colour = STATES.fetch(state)
        puts "    #{paint(label.ljust(5), colour)} " \
             "#{name.to_s.ljust(22)} #{detail}"
        state == :block ? 1 : 0
    end

    def gems
        return item(:ok, "gems", "installed") if
            system("bundle check > /dev/null 2>&1")

        item(:block, "gems", "not installed -- run: bundle install")
    end

    # Derived from the tracked examples rather than listed: the house
    # rule is that every file a deployment must supply has an .example
    # beside it, so the examples ARE the list, and one added later is
    # covered without anyone remembering to come back here.
    #
    # Having an example is also what MAKES a file the deployment's,
    # which is the other half checked here: it must exist, and it must
    # not be tracked. A committed one carries this machine's addresses
    # and whatever key it holds into everyone else's checkout, and
    # nothing else ever notices, because the service runs perfectly.
    def files
        # Anywhere they are kept, not just where they were the day
        # this was written: a glob rooted at "*" stops finding them
        # the moment somebody tidies config into a directory, and
        # then reports "nothing required" rather than failing.
        examples = Dir["*.example", "config/*.example"]
        return item(:ok, "config", "nothing required") if examples.empty?

        examples.sum { local_file(it) } +
            examples.sum { shared_file(it) }
    end

    # Where this machine's local file lives, outside the checkout
    # ($LEDGER_VIEWER_LOCAL names another, as the loader honours it).
    def local_place(example)
        ENV.fetch("LEDGER_VIEWER_LOCAL", nil) ||
            File.join(Dir.home, ".config", "ledger-viewer",
                      File.basename(example, ".example"))
    end

    def local_file(example)
        name = local_place(example)
        return item(:block, name, "missing -- copy #{example} there") unless
            File.exist?(name)
        unless tracked?(name)
            return item(:ok, name, "present, untracked") + keys(example, name)
        end

        item(:warn, name, "TRACKED -- it names this deployment. " \
                          "git rm --cached #{name}")
    end

    # The example is the contract for the local file's keys. One it
    # sets and the local file omits is a setting that quietly falls
    # back to a default -- which is how a service came up reading half
    # a config -- so it blocks. One the example never mentions is most
    # likely a typo the loader will ignore, so it warns.
    def keys(example, name)
        wanted = keys_of(example)
        got    = keys_of(name)
        return 0 unless wanted && got

        unknown_keys(name, got - wanted)
        missing = wanted - got
        return 0 if missing.empty?

        item(:block, name, "missing key(s) #{missing.join(", ")} -- " \
                           "the example sets them")
    end

    def unknown_keys(name, unknown)
        return if unknown.empty?

        item(:warn, name, "unknown key(s) #{unknown.join(", ")} -- typo?")
    end

    # Both halves are plain ruby returning a Hash (SKILL.md), so the
    # keys are read by evaluating the file. Anything else -- another
    # format, a file that does not parse -- is left to the loader to
    # report.
    def keys_of(file)
        return nil unless file.end_with?(".rb", ".rb.example")

        value = Object.new.instance_eval(File.read(file), file, 1)
        value.is_a?(Hash) ? value.keys.map(&:to_s).sort : nil
    rescue StandardError, SyntaxError
        nil
    end

    # The counterpart of a `<name>.local.<ext>`: the same name without
    # the infix, holding what is true of the program rather than of
    # this machine. It is meant to be committed, so a checkout behaves
    # the same before anyone writes a local file.
    def shared_file(example)
        local = example.sub(/\.example\z/, "")
        return 0 unless local.include?(".local.")

        name = local.sub(".local.", ".")
        unless File.exist?(name)
            return item(:warn, name, "absent -- the program's own " \
                                     "settings fall back to defaults")
        end
        return item(:ok, name, "present, tracked") if tracked?(name)

        item(:warn, name, "NOT tracked -- other checkouts will not get it")
    end

    # False outside a git checkout: a deployment unpacked from a
    # tarball has no opinion about what is tracked, and inventing one
    # would report every file as a problem.
    def tracked?(name)
        return false unless File.directory?(".git")

        system("git ls-files --error-unmatch #{name.shellescape} " \
               "> /dev/null 2>&1")
    end

    def tools
        TOOLS.sum do |name, purpose|
            found = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
                       .map { File.join(it, name) }
                       .find { File.executable?(it) }
            next item(:ok, name, found) if found

            item(:warn, name, "absent -- #{purpose} will fail")
        end
    end

    # A house service has exactly one umbrella, lib/<name>.rb, and
    # requiring it is what defines the settings class. Finding it
    # beats naming it: a named one goes stale on a rename and, worse,
    # a template shipped with somebody else's name checks their
    # project and reports this one healthy. A checkout holding more than
    # one program (lib/ledger.rb beside lib/ledger_viewer.rb) has the
    # served one named by its launcher: bin/ledger-viewer serves
    # lib/ledger_viewer.rb.
    def umbrella
        found = Dir["lib/*.rb"]
        return found.first if found.size == 1
        return served_umbrella if found.include?(served_umbrella)

        why = if found.empty?
                  "no lib/*.rb to load"
              else
                  "#{found.size} candidates in lib/ -- cannot pick one"
              end
        item(:warn, "settings", why)
        nil
    end

    # lib/<launcher>.rb, the launcher's dashes as underscores; nil
    # without a launcher.
    def served_umbrella
        launcher&.then { "lib/#{File.basename(it).tr("-", "_")}.rb" }
    end

    # The module the umbrella defined, identified by having a Config
    # that answers `load` -- the only thing anything here needs of it.
    #
    # Asked by name first: lib/<name>.rb defines <Name> by house
    # convention. The scan of what the require ADDED is only the
    # fallback, and it is not trusted on its own, because the
    # umbrella's own requires drag in constants that also fit --
    # OpenSSL::Config answers `load` -- and a pre-flight that loaded
    # OpenSSL's settings reported "loaded" and then printed no
    # address, no data directory and no networks.
    def settings_module(file)
        before = Object.constants
        require File.expand_path(file, Dir.pwd)

        named = constant(File.basename(file, ".rb")
                             .split(/[_-]/).map(&:capitalize).join)
        return named if named && configured?(named)

        (Object.constants - before).filter_map { constant(it) }
                                   .find { configured?(it) }
    end

    # StandardError rather than NameError alone: touching a registered
    # autoload whose file refuses to load raises whatever it likes.
    def constant(name)
        Object.const_get(name)
    rescue StandardError
        nil
    end

    def configured?(thing)
        thing.is_a?(Module) && thing.const_defined?(:Config) &&
            thing.const_get(:Config).respond_to?(:load)
    end

    # Loaded once per rake run and kept: settings_module tells the
    # umbrella by what its require ADDS, and a second require adds
    # nothing, so without this `rake check status` found the settings
    # once and then reported them missing.
    @loaded = nil

    class << self
        attr_accessor :loaded
    end

    def settings(quiet: false)
        Preflight.loaded ||= load_settings
        config, file = Preflight.loaded
        return [nil, 0] unless file
        return [nil, no_config(file)] unless config

        item(:ok, "settings", "#{file} loaded") unless quiet
        [config, 0]
    rescue StandardError => e
        [nil, item(:block, "settings", failure(e))]
    end

    def load_settings
        file = umbrella or return [nil, nil]
        found = settings_module(file)
        [found&.const_get(:Config)&.load, file]
    end

    def no_config(file)
        item(:warn, "settings", "#{file} defines no Config.load")
    end

    def failure(error)
        "#{error.class}: #{error.message.lines.first.to_s.strip}"
    end

    # Free, taken, or not assignable at all -- three outcomes, and the
    # third is the one nobody expects: an address no longer on this
    # machine because an interface went away or a digit is wrong. The
    # first two want opposite reactions, so they are never merged.
    def address(spec)
        host, _, port = spec.rpartition(":")
        TCPServer.new(host, Integer(port)).close
        item(:ok, spec, "free")
    rescue Errno::EADDRINUSE
        Preflight.busy += 1
        item(:warn, spec, "in use -- already running, or something else is")
    rescue SystemCallError => e
        item(:block, spec, "cannot bind: #{e.class.name.split("::").last}")
    end

    def addresses(config)
        return 0 unless config.respond_to?(:bind)

        config.bind.sum { address(it) }
    end

    def listening(config)
        return unless config.respond_to?(:bind)

        config.bind.each { item(*listening_state(it)) }
    end

    def listening_state(spec)
        host, _, port = spec.rpartition(":")
        TCPServer.new(host, Integer(port)).close
        [:info, spec, "nothing listening"]
    rescue Errno::EADDRINUSE
        [:ok, spec, "in use -- something is serving here"]
    rescue SystemCallError => e
        [:block, spec, "not assignable here (#{e.class.name.split("::").last})"]
    end

    # Sinatra reads APP_ENV ahead of RACK_ENV, so a stray one in the
    # shell is the mode whatever RACK_ENV says.
    def mode
        app_env = ENV.fetch("APP_ENV", nil)
        return "#{app_env} (APP_ENV, ahead of RACK_ENV)" if app_env

        ENV.fetch("RACK_ENV", "development (RACK_ENV unset)")
    end

    # Facts, so :info -- except a data directory that exists and
    # cannot be written, which is the one line here that predicts a
    # failure rather than describing a state.
    def settings_report(config)
        item(:info, "mode", mode)
        data_report(config)
        # to_s drops the prefix length, so a /24 would print as a bare
        # address and read as one host rather than two hundred.
        if config.respond_to?(:lan)
            item(:info, "trusted networks",
                 config.lan.map { "#{it}/#{it.prefix}" }.join(", "))
        end
        item(:info, "permitted hosts", config.permitted_hosts.join(", ")) if
            config.respond_to?(:permitted_hosts)
    end

    # The store file's name, then the state of the directory it is in.
    def data_report(config)
        return unless config.respond_to?(:data_dir)

        item(:info, "store", config.store)
        item(*data_state(config.data_dir))
    end

    # puma writes this when config/puma.rb says `pidfile "tmp/puma.pid"`.
    # Without it stop and restart would have to guess at a process
    # from a command line, which is how the wrong server gets killed
    # on a machine running two of them -- and puma retitles itself
    # (`puma 8.0.2 (unix:///...) [dir]`), so the command line it was
    # launched with is not even there to match.
    PIDFILE = "tmp/puma.pid"

    # How long stop waits after TERM. Puma drains requests in flight
    # for up to `force_shutdown_after` seconds, so a shorter wait
    # reports a failed stop while puma is doing what it was told. Read
    # from config/puma.rb rather than repeated here, so the two cannot
    # drift; 15s when it sets none, since puma then waits forever.
    # Only a literal number is read: a value taken from settings or a
    # constant falls back to 15s, so write it as a number there.
    def stop_wait
        file = "config/puma.rb"
        text = File.exist?(file) ? File.read(file) : ""
        seconds = text[/^\s*force_shutdown_after\s+(\d+)/, 1]
        seconds ? Integer(seconds) + 5 : 15
    end

    # The executable in bin/ that serves the app, or ./run -- the two
    # shapes a launcher takes here. Found rather than named, like
    # everything else, so this file stays free of one project's
    # spelling: bin/ may hold the project's other programs too, and the
    # launcher is then the one that execs puma.
    def launcher
        found = Dir["bin/*"].select { File.executable?(it) }
        found = found.select { serves?(it) } if found.size > 1
        return found.first if found.size == 1
        return "./run" if File.executable?("run")

        nil
    end

    # Whether the program at PATH starts the server: a line execing puma.
    def serves?(path)
        File.foreach(path).any? { it.match?(/^\s*exec\b.*\bpuma\b/) }
    rescue SystemCallError, ArgumentError
        false
    end

    # The running pid, or nil. A pidfile outlives the process it
    # named, so the file existing is not the question -- whether
    # signal 0 reaches anything is.
    def running_pid
        return nil unless File.exist?(PIDFILE)

        value = Integer(File.read(PIDFILE).strip, exception: false)
        return nil unless value

        Process.kill(0, value)
        value
    rescue Errno::ESRCH
        nil
    rescue Errno::EPERM
        value
    end

    # Bind addresses currently held by something. Asked by start when
    # it has no pid of its own, to tell "already running" apart from
    # "someone else is on our port".
    def taken_addresses
        config, = settings(quiet: true)
        return [] unless config.respond_to?(:bind)

        config.bind.reject { free_address?(it) }
    end

    def free_address?(spec)
        host, _, port = spec.rpartition(":")
        TCPServer.new(host, Integer(port)).close
        true
    rescue Errno::EADDRINUSE
        false
    rescue SystemCallError
        true
    end

    def clear_stale_pidfile
        FileUtils.rm_f(PIDFILE)
    end

    # The store's directory holds every user's credentials: a directory
    # others can read or enter blocks, since the file inside is only as
    # private as the way to it.
    def data_state(dir)
        return [:info, "data", "#{dir} -- will be created"] unless
            File.exist?(dir)
        return [:warn, "data", "#{dir} -- NOT writable"] unless
            File.writable?(dir)
        if File.stat(dir).mode.anybits?(0o077)
            return [:block, "data", "#{dir} -- others can read it: " \
                                    "chmod 700 #{dir}"]
        end

        [:info, "data", "#{dir} -- writable, private"]
    end
end
