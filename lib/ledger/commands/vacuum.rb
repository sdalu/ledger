# frozen_string_literal: true

require "ledger/vacuum"

module Ledger
    module Commands
        # `vacuum [--dry-run]`: the journal's free pages given back to
        # the file. The journal is first copied (Backup) to
        # <journal>.before-vacuum-YYYYMMDD-HHMMSS, then VACUUM runs once
        # no other session holds the write lock.
        class Vacuum < CLI::Command
            USAGE = ""
            SYNOPSIS = "[--dry-run]"
            SUMMARY = "compact the journal after a backup copy; not an " \
                      "event, so undo and restore cannot bring the old " \
                      "file back, only the backup. Refused while another " \
                      "session is writing. With --dry-run, print the " \
                      "journal's size and free pages and change nothing"

            private

            def flags(parser)
                parser.on("--dry-run", "print the sizes; write nothing") do
                    @opts[:dry_run] = true
                end
            end

            def run
                vacuum = Ledger::Vacuum.new(journal)
                return report(vacuum.sizes) if @opts[:dry_run]

                done(*vacuum.run)
            rescue Backup::Exists => e
                refuse("#{e.message}; nothing vacuumed")
            rescue Ledger::Vacuum::Busy => e
                refuse("#{e.message}\nbackup kept: #{e.backup}")
            end

            def report(sizes)
                @out.puts "page_count: #{sizes.pages}"
                @out.puts "freelist_count: #{sizes.free}"
                @out.puts "page_size: #{sizes.page_size}"
                @out.puts "size: #{sizes.bytes} bytes, " \
                          "#{sizes.free_bytes} free"
                0
            end

            def done(path, before, after)
                @out.puts "size before: #{before.bytes} bytes"
                @out.puts "size after: #{after.bytes} bytes"
                @out.puts "backup: #{path}"
                0
            end
        end
    end
end
