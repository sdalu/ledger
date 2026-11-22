# frozen_string_literal: true

require "digest"
require "fileutils"
require "open3"

require "ledger/hooks/edit_record"
require "ledger/hooks/ledgers"

module Ledger
    module Hooks
        # Stop: the files the session edited (edit-record) that a git
        # repository still shows as changed, in a repository whose
        # project has a live ledger with no piece awaiting commit and no
        # piece out, are named back to the session once per distinct set
        # of files. A plain dirty-tree test would name other sessions'
        # work in a shared tree; the record keeps it to this session's
        # own files. A repository with no live ledger is never named, and
        # a session with no record passes. On the retry
        # (stop_hook_active) the stop goes through.
        module Uncommitted
            STEPS = "files you edited are uncommitted and no piece awaits " \
                    "commit: %<paths>s; file one with --awaits commit " \
                    "(its scope naming them), or say why not"

            module_function

            def call(payload)
                return Answer.pass if payload["stop_hook_active"]

                id = payload["session_id"].to_s
                return Answer.pass unless EditRecord::BARE.match?(id)

                paths = named(payload, EditRecord.record(id))
                return Answer.pass if paths.empty? || sent?(id, paths)

                remember(id, paths)
                Answer.refuse(format(STEPS, paths: paths.join(", ")))
            end

            # The recorded paths, still changed, in repositories that
            # call for a commit; sorted.
            def named(payload, record)
                return [] unless File.file?(record)

                due = due_repositories(Ledgers.read(payload))
                return [] if due.empty?

                changed(File.readlines(record, chomp: true), due).sort
            end

            # The top directories of the repositories whose every live
            # ledger has no piece awaiting commit and none out.
            def due_repositories(found)
                by_top = found.group_by { top(project(it.address)) }
                by_top.delete(nil)
                by_top.select { |_, list| list.all? { idle?(it.derive) } }.keys
            end

            # The directory a ledger's address belongs to: a LEDGER.md
            # under `.claude` is its project's.
            def project(address)
                dir = File.dirname(address)
                File.basename(dir) == ".claude" ? File.dirname(dir) : dir
            end

            def idle?(derive)
                live = derive.pieces.select { derive.unfinished?(it) }
                live.none? { out_or_awaiting?(derive, it) }
            end

            def out_or_awaiting?(derive, piece)
                piece[:status] == "out" ||
                    derive.awaits(piece).any? { |word, _| word == "commit" }
            end

            def changed(paths, due)
                paths.select do |path|
                    top = top(File.dirname(path))
                    due.include?(top) && dirty?(top, path)
                end
            end

            # The repository's top directory for DIR; nil outside one.
            def top(dir)
                return unless File.directory?(dir)

                out, _, status = Open3.capture3("git", "-C", dir, "rev-parse",
                                                "--show-toplevel")
                status.success? ? File.realpath(out.chomp) : nil
            end

            def dirty?(top, path)
                out, _, status = Open3.capture3("git", "-C", top, "status",
                                                "--porcelain", "--", path)
                status.success? && !out.strip.empty?
            end

            def digest(paths) = Digest::SHA256.hexdigest(paths.join("\n"))

            def digest_file(id) = "#{EditRecord.record(id)}.sent"

            def sent?(id, paths)
                file = digest_file(id)
                File.file?(file) && File.read(file).chomp == digest(paths)
            end

            # Written to a temp path and renamed: an interrupt leaves the
            # old digest or the new.
            def remember(id, paths)
                file = digest_file(id)
                FileUtils.mkdir_p(File.dirname(file))
                tmp = "#{file}.#{Process.pid}"
                File.write(tmp, "#{digest(paths)}\n")
                File.rename(tmp, file)
            end
        end
    end
end
