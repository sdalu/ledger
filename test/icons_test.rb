# frozen_string_literal: true

require "digest"
require "test_helper"

# Every icon is pinned by the SHA-256 of its SVG, so that a change to
# icons.json or to the drawing code fails here. support/icon_digests.json
# maps each icon name to the digest of the SVG `Icons.icon(name)` returns.
class IconsTest < Minitest::Test
    DIGESTS = JSON.parse(
        File.read(File.join(__dir__, "support", "icon_digests.json"))
    ).freeze

    def test_the_icon_names_are_the_pinned_ones
        assert_equal DIGESTS.keys.sort, LedgerViewer::Render::Icons.names.sort
    end

    def test_every_icon_draws_the_pinned_svg
        DIGESTS.each do |name, digest|
            svg = LedgerViewer::Render::Icons.icon(name)

            assert_equal digest, Digest::SHA256.hexdigest(svg), name
        end
    end
end
