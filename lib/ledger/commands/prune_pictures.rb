# frozen_string_literal: true

require "ledger/backup"
require "ledger/prune_pictures"

module Ledger
    module Commands
        # `prune-pictures [L<n>] [--older DAYS] [--confirmed]`: the
        # pictures no piece, question or choice names any more, and the
        # stored contents no picture points to. Without --confirmed it
        # lists them and writes nothing; with it, the journal is first
        # copied (Backup), then one transaction deletes them.
        class PrunePictures < CLI::Command
            USAGE = "[L<n>]"
            SYNOPSIS = "[L<n>] [--older DAYS] [--confirmed]"
            LEDGER = /\AL([1-9]\d*)\z/
            DEFAULT_DAYS = 7
            SUMMARY = "remove the pictures nothing names, placed more than " \
                      "DAYS ago (7 by default), and the stored contents no " \
                      "picture points to, after a backup copy; not an " \
                      "event, so undo and restore cannot bring them back " \
                      "(a picture they reach shows as gone), only the " \
                      "backup. L<n> limits it to one ledger. Without " \
                      "--confirmed, list what would go and write nothing; " \
                      "`ledger vacuum` then shrinks the file"

            private

            def flags(parser)
                parser.on("--older DAYS", Integer,
                          "only pictures placed more than DAYS ago " \
                          "(#{DEFAULT_DAYS})") { @opts[:older] = it }
                parser.on("--confirmed", "do it, after the backup") do
                    @opts[:confirmed] = true
                end
            end

            def run(name = nil)
                days = @opts.fetch(:older, DEFAULT_DAYS)
                refuse("--older is not negative") if days.negative?
                prune = Ledger::PrunePictures.new(
                    journal.db, ledger_id: ledger_id(name), older: days
                )
                unused = prune.unused
                return list(unused, prune.counts) unless @opts[:confirmed]

                confirmed(prune, unused)
            end

            # The id L<n> names, refused when there is no such ledger;
            # nil for every ledger.
            def ledger_id(name)
                return unless name

                match = LEDGER.match(name) or
                    refuse("#{name} is not a ledger id (L<n>)")
                journal.ledger_by_id(match[1].to_i)[:id]
            end

            def list(unused, counts)
                unused.each { @out.puts row(it) }
                @out.puts "would remove #{totals(counts)}"
                @out.puts "dry run: nothing written; --confirmed removes them"
                0
            end

            # "L1 O3 shot.png (2 files) 1024 bytes placed 2026-11-01".
            def row(item)
                files = item.files > 1 ? " (#{item.files} files)" : ""
                placed = Time.at(item.placed / 1000).strftime("%F")
                "L#{item.ledger_id} #{item.owner || "-"} " \
                    "#{item.name}#{files} #{item.bytes} bytes placed #{placed}"
            end

            def totals(counts)
                "#{counts.pictures} picture rows, #{counts.blobs} stored " \
                    "contents, #{counts.bytes} bytes"
            end

            def confirmed(prune, unused)
                counts = prune.counts
                if counts.pictures.zero? && counts.blobs.zero?
                    @out.puts "nothing to prune"
                    return 0
                end
                path = backup
                report(unused, journal.transaction { prune.delete }, path)
            end

            def report(unused, done, path)
                unused.each { @out.puts row(it) }
                @out.puts "removed #{totals(done)}"
                @out.puts "backup: #{path}"
                @out.puts "ledger vacuum shrinks the file"
                0
            end

            # The journal copied beside itself; refused when the name is
            # taken, before anything is removed.
            def backup
                path = Backup.prune_path(journal.path)
                Backup.copy(journal.db, path)
                path
            rescue Backup::Exists => e
                refuse("#{e.message}; nothing pruned")
            end
        end
    end
end
