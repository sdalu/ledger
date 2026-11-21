# frozen_string_literal: true

require "json"

module Ledger
    module Waker
        # Whether Claude Code trusts a directory, as its own configuration
        # (~/.claude.json, read only, never written) says: a project entry
        # for the directory or one above it with the trust dialog
        # accepted. Nothing else of that file is looked at.
        module Trust
            CONFIG = "~/.claude.json"
            KEY = "hasTrustDialogAccepted"
            # What the trust dialog shows on the screen.
            DIALOG = "Yes, I trust this folder"

            module_function

            # :trusted, :untrusted, or :unknown when the file cannot be
            # read as expected.
            def of(dir, config: File.expand_path(CONFIG))
                projects = JSON.parse(File.read(config))["projects"]
                return :unknown unless projects.is_a?(Hash)

                accepted = ancestors(File.expand_path(dir))
                           .any? { projects.dig(it, KEY) == true }
                accepted ? :trusted : :untrusted
            rescue SystemCallError, JSON::ParserError, TypeError
                :unknown
            end

            # DIR and every directory above it, DIR first.
            def ancestors(dir)
                [dir].tap do |list|
                    list << File.dirname(list.last) until
                        list.last == File.dirname(list.last)
                end
            end
        end
    end
end
