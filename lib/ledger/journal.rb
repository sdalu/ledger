# frozen_string_literal: true

require "fileutils"

require "sequel"
require "sesam"

module Ledger
    # The file name a ledger's address ends in.
    ADDRESS_FILE = %r{\ALEDGER(?:-(?<name>[^/]+))?\.md\z}

    # A ledger's address: the path its file had, PLACE/LEDGER.md or
    # PLACE/LEDGER-NAME.md, resolved against the current directory and
    # never touched on disk.
    Address = Data.define(:place, :name) do
        # Address.parse("../x/LEDGER-web.md") => place: /abs/x, name: "web".
        def self.parse(path)
            full = File.expand_path(path)
            match = ADDRESS_FILE.match(File.basename(full))
            raise Unknown, "not a ledger address: #{path}" unless match
            new(place: File.dirname(full), name: match[:name] || "")
        end

        def file = name.empty? ? "LEDGER.md" : "LEDGER-#{name}.md"
        def to_s = File.join(place, file)
    end

    # The journal file: opened in WAL mode with foreign keys on, a busy
    # timeout for writers, and both migration sets run (sesam's first).
    class Journal
        DEFAULT = "~/.local/state/orchestration/journal.db"
        BUSY_MS = 10_000
        MIGRATIONS = File.expand_path("migrations", __dir__)
        SCHEMA_TABLE = :ledger_schema
        KINDS = %w[P O D C F N X G].freeze

        # LEDGER_JOURNAL names another file (tests, a sandbox).
        def self.path
            ENV.fetch("LEDGER_JOURNAL") { File.expand_path(DEFAULT) }
        end

        def self.open(path = self.path, busy_ms: BUSY_MS)
            new(path, busy_ms:)
        end

        attr_reader :path, :db

        def initialize(path, busy_ms: BUSY_MS)
            @path = path
            make_directory
            @db = Sequel.sqlite(path, timeout: busy_ms, foreign_keys: true)
            File.chmod(0o600, path)
            @db.run("PRAGMA journal_mode = WAL")
            migrate
        end

        def close = db.disconnect

        # BEGIN IMMEDIATE: the write lock is taken before anything is
        # read; a writer still waiting after the busy timeout is refused.
        def transaction(&)
            db.transaction(mode: :immediate, &)
        rescue Sequel::DatabaseError => e
            raise Locked if e.wrapped_exception.is_a?(SQLite3::BusyException)
            raise
        end

        # The live ledger at an address, as a row; Unknown when none.
        def ledger(address)
            address = parse_near(address) unless address.is_a?(Address)
            row = db[:ledgers].where(place: address.place, name: address.name,
                                     closed_at: nil).first
            return row if row

            raise Unknown, near("no live ledger at #{address}", address.place)
        end

        # The live ledgers at DIR or under it, as addresses, sorted.
        def live_under(dir)
            under = Sequel.like(:place, "#{db.dataset.escape_like(dir)}/%")
            db[:ledgers].where(closed_at: nil)
                        .where(Sequel.|({ place: dir }, under))
                        .order(:place, :name)
                        .map { Address.new(place: it[:place], name: it[:name]) }
        end

        # A ledger row by its id (`L<id>`), live or closed.
        def ledger_by_id(id)
            db[:ledgers].where(id:).first or
                raise Unknown, "no ledger L#{id}"
        end

        # A new live ledger at an address, its counters at zero. The row
        # is the command's to announce; no event is written here.
        def create_ledger(address, project:, at: Write.now)
            address = Address.parse(address) unless address.is_a?(Address)
            transaction do
                id = db[:ledgers].insert(place: address.place,
                                         name: address.name, project:,
                                         created_at: at)
                KINDS.each { db[:counters].insert(ledger_id: id, kind: it) }
                db[:ledgers].where(id:).first
            end
        end

        # How many ledgers a refusal lists before it says how many more.
        NEAR_SHOWN = 10
        private_constant :NEAR_SHOWN

        private

        # Address.parse, its refusal naming the form an address takes and
        # the live ledgers at the path or under it: a directory given for
        # an address is the usual slip.
        def parse_near(path)
            Address.parse(path)
        rescue Unknown => e
            form = "#{e.message} (an address ends in LEDGER.md or " \
                   "LEDGER-NAME.md)"
            raise Unknown, near(form, File.expand_path(path))
        end

        # MESSAGE, then the live ledgers at DIR or under it, one a line.
        def near(message, dir)
            found = live_under(dir)
            return message if found.empty?

            shown = found.first(NEAR_SHOWN).map { "  #{it}" }
            more = found.size - shown.size
            shown << "  ... and #{more} more" if more.positive?
            [message, "live ledgers under #{dir}:", *shown].join("\n")
        end

        # The directory is made 0700: the file holds password hashes.
        def make_directory
            dir = File.dirname(path)
            return if File.directory?(dir)
            FileUtils.mkdir_p(dir, mode: 0o700)
        end

        def migrate
            Sequel.extension :migration
            Sesam.migrate(db)
            Sequel::Migrator.run(db, MIGRATIONS, table: SCHEMA_TABLE)
        end
    end
end
