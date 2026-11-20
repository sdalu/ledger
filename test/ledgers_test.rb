# frozen_string_literal: true

require "test_helper"

# What the index's ties and links lean on: the order ledgers are found
# in, the id, and where the pictures are.
class LedgersTest < Minitest::Test
    def setup = @dir = Dir.mktmpdir("ledgers", SANDBOX)

    def ledger(project, name = "LEDGER.md", sub: ".claude")
        dir = File.join(@dir, project, sub)
        FileUtils.mkdir_p([dir, File.join(@dir, project, ".git")])
        File.write(File.join(dir, name), "# Ledger\n")
    end

    def found = LedgerViewer::Ledgers.new([@dir]).all

    def test_the_order_is_the_searchs_not_a_sort
        ledger("a", sub: ".")
        ledger("a", sub: ".claude")
        ledger("a-b")

        paths = found.map { it.path.delete_prefix("#{@dir}/") }

        assert_equal %w[a/LEDGER.md a/.claude/LEDGER.md a-b/.claude/LEDGER.md],
                     paths
    end

    def test_the_mockups_folder_follows_the_engines_rule
        ledger("p")
        entry = found.first

        assert_equal File.join(@dir, "p/.claude/mockups"), entry.mockups
        loose = LedgerViewer::Ledgers::Entry.new(
            id: "x", path: "/t/l/LEDGER.md", project: "/t/l"
        )

        assert_equal "/t/l/mockups", loose.mockups
    end
end
