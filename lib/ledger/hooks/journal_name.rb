# frozen_string_literal: true

module Ledger
    module Hooks
        # Whether a word of a command names the journal file or one of its
        # SQLite companions (-wal, -shm, -journal). `~`, `$HOME` and
        # `$LEDGER_JOURNAL` are expanded; an absolute word must then be
        # the journal's own path, a relative one (which a `cd` earlier in
        # the command may have aimed anywhere) only needs its file name.
        #
        #     name = JournalName.new("/home/u/.local/state/o/journal.db")
        #     name.match?("~/.local/state/o/journal.db-wal")  # => true
        #     name.match?("journal.db")                       # => true
        #     name.match?("/tmp/other/journal.db")            # => false
        class JournalName
            # Journal::DEFAULT, repeated so this file needs no Sequel;
            # a test keeps the two equal.
            DEFAULT = "~/.local/state/orchestration/journal.db"
            SUFFIXES = ["", "-wal", "-shm", "-journal"].freeze
            VARIABLE = /\$(?:\{LEDGER_JOURNAL\}|LEDGER_JOURNAL\b)/
            HOME = /\$(?:\{HOME\}|HOME\b)/
            # What may follow the file name in a mention: a companion's
            # suffix, then no more of a name.
            TAIL = "(?:-wal|-shm|-journal)?(?![\\w.-])"

            # The journal the hook's own environment names, as Journal.path
            # finds it.
            def self.current
                new(ENV.fetch("LEDGER_JOURNAL") { File.expand_path(DEFAULT) })
            end

            attr_reader :path

            # The home `~` and $HOME expand to; nil when none is known (a
            # hook started with env -i), which leaves them as written.
            def self.home
                Dir.home
            rescue ArgumentError
                nil
            end

            def initialize(path, home: JournalName.home)
                @path = File.expand_path(path)
                @home = home
                base = File.basename(@path)
                @paths = SUFFIXES.map { @path + it }
                @bases = SUFFIXES.map { base + it }
                @mention = /[^\s'"(),;]*#{Regexp.escape(base)}#{TAIL}/
            end

            # A command that cannot name the journal is not read further.
            def mentioned?(command)
                command.include?(File.basename(@path)) ||
                    command.include?("LEDGER_JOURNAL")
            end

            def match?(word)
                word = expand(word)
                return @paths.include?(File.expand_path(word)) if
                    word.start_with?("/")
                @bases.include?(File.basename(word))
            end
            alias === match?

            # The words of CODE (a script's text) that name the journal.
            def mentions(code)
                code.gsub(VARIABLE, @path).scan(@mention).select { match?(it) }
            end

            private

            def expand(word)
                word = word.gsub(VARIABLE, @path)
                return word unless @home
                word.sub(%r{\A~(?=/|\z)}, @home).gsub(HOME, @home)
            end
        end
    end
end
