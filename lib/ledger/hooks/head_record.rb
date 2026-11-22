# frozen_string_literal: true

require "fileutils"
require "open3"

require "ledger/hooks/edit_record"

module Ledger
    module Hooks
        # What a session has seen of its repositories' HEADs, kept in
        # `heads/SESSION_ID` beside the journal file, one `TOP<TAB>HEAD`
        # line per repository: the commits HEAD gained since the last
        # sight.
        module HeadRecord
            ABBREV = 7

            module_function

            # The abbreviated ids HEAD gained in the repository at DIR
            # since the session last saw it; [] when it did not move or
            # was never seen.
            def moved(id, dir)
                top = git(dir, "rev-parse", "--show-toplevel").first
                head = git(dir, "rev-parse", "HEAD").first
                return [] unless top && head

                seen = heads(id)
                remember(id, seen.merge(top => head))
                old = seen[top]
                return [] if old.nil? || old == head

                git(top, "rev-list", "--reverse", "--abbrev-commit",
                    "--abbrev=#{ABBREV}", "#{old}..#{head}")
            end

            # The output lines of git in DIR; [] when it fails or DIR is
            # no directory.
            def git(dir, *)
                return [] unless File.directory?(dir)

                out, _, status = Open3.capture3("git", "-C", dir, *)
                status.success? ? out.lines(chomp: true) : []
            end

            # {repository top => the HEAD last seen}.
            def heads(id)
                file = memory(id)
                return {} unless File.file?(file)

                File.readlines(file, chomp: true).to_h { it.split("\t", 2) }
            end

            def memory(id)
                dir = File.dirname(EditRecord.record(id), 2)
                File.join(dir, "heads", id)
            end

            # Written to a temp path and renamed: an interrupt leaves the
            # old record or the new.
            def remember(id, heads)
                file = memory(id)
                FileUtils.mkdir_p(File.dirname(file))
                tmp = "#{file}.#{Process.pid}"
                lines = heads.map { |top, head| "#{top}\t#{head}\n" }
                File.write(tmp, lines.join)
                File.rename(tmp, file)
            end
        end
    end
end
