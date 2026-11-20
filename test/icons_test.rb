# frozen_string_literal: true

require "test_helper"

# Every icon is the one viewer_icons.py draws: icons.json is a dump of
# its tables, and this is what fails when they drift.
class IconsTest < Minitest::Test
    PYTHON = File.expand_path("support/python_icons.py", __dir__)

    def test_every_icon_is_the_pythons
        out, status = Open3.capture2("python3", PYTHON)

        assert_predicate status, :success?
        python = JSON.parse(out)

        assert_equal python.keys.sort, LedgerViewer::Render::Icons.names.sort
        python.each do |name, svg|
            assert_equal svg, LedgerViewer::Render::Icons.icon(name), name
        end
    end
end
