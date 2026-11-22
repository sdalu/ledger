# frozen_string_literal: true

require "fileutils"

module Ledger
    module Hooks
        # PostToolUse on Edit, Write and NotebookEdit: the absolute path
        # the tool edited is appended to the session's record, one path
        # per line, no duplicates, in `edits/SESSION_ID` beside the
        # journal file (LEDGER_JOURNAL moves both). `uncommitted` reads
        # that record at Stop. It denies nothing and answers nothing;
        # the standard library alone, since it runs after every edit.
        module EditRecord
            DEFAULT = "~/.local/state/orchestration/journal.db"
            # A session id is one path component: no separator, no dot
            # lead.
            BARE = /\A[A-Za-z0-9][A-Za-z0-9_-]*\z/

            module_function

            def call(payload)
                id = payload["session_id"].to_s
                path = edited(payload["tool_input"])
                append(record(id), path) if BARE.match?(id) && path
                Answer.pass
            end

            # The record file of session ID, beside the journal.
            def record(id)
                journal = ENV.fetch("LEDGER_JOURNAL") do
                    File.expand_path(DEFAULT)
                end
                File.join(File.dirname(journal), "edits", id)
            end

            # The edited file's absolute path, nil when the input names none.
            def edited(input)
                return unless input.is_a?(Hash)

                path = input["file_path"] || input["notebook_path"]
                return if path.to_s.empty?

                File.expand_path(path.to_s)
            end

            def append(file, path)
                FileUtils.mkdir_p(File.dirname(file))
                return if File.exist?(file) &&
                          File.readlines(file, chomp: true).include?(path)

                File.open(file, "a") { it.puts path }
            end
        end
    end
end
