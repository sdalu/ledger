# frozen_string_literal: true

require "test_helper"

# What is committed is the program, not the deployment running it: no
# private address (RFC 1918) and no name of the estate in a file the
# repository would carry; documentation values instead (RFC 5737's
# 192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24, example.com). And the
# other way: what the program is made of must be in the repository (the
# shared config, every rake file), what names this deployment must not
# be (config/app.local.rb).
#
# "In the repository" is what git would take: tracked, or not yet added
# and not ignored. A file the ignore rules hide is in neither list.
#
# The estate's names are not written here, which would be the leak: an
# untracked test/local.rb may define PRIVATE_NAMES, and the guard then
# looks for them too.
class TrackedFilesTest < Minitest::Test
    ROOT = File.expand_path("..", __dir__)

    local = File.join(__dir__, "local.rb")
    load local if File.exist?(local)
    NAMES = defined?(PRIVATE_NAMES) ? PRIVATE_NAMES : []

    PRIVATE = /\b(?:10(?:\.\d{1,3}){3}|192\.168(?:\.\d{1,3}){2}|
                   172\.(?:1[6-9]|2\d|3[01])(?:\.\d{1,3}){2})\b/x

    def carried
        @carried ||= Dir.chdir(ROOT) do
            IO.popen(%w[git ls-files -z --cached --others --exclude-standard],
                     &:read).split("\0")
        end
    end

    def read(file) = File.binread(File.join(ROOT, file))

    def test_no_file_holds_a_private_address
        found = carried.select { File.file?(File.join(ROOT, it)) }
                       .select { read(it).match?(PRIVATE) }

        assert_empty found, "files with an RFC 1918 address"
    end

    def test_no_file_names_the_estate
        found = carried.select do |file|
            text = read(file)
            NAMES.any? { text.include?(it) }
        end

        assert_empty found, "files naming the estate"
    end

    def test_what_the_program_is_made_of_is_in_the_repository
        made_of = ["config/app.rb", "config/app.local.rb.example",
                   "config/puma.rb", "config.ru", "bin/ledger-viewer",
                   *Dir.chdir(ROOT) { Dir["rakelib/*.rake"] }]

        assert_empty made_of - carried, "parts of the program left out"
    end

    def test_the_deployment_is_not_in_the_repository
        refute_includes carried, "config/app.local.rb"
        refute(carried.any? { it.start_with?("tmp/", "data/", "config/tls/") })
    end
end
