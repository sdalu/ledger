# frozen_string_literal: true

module LedgerViewer
    # A urlencoded body (or a query) read the way parse_qs of the
    # urlencoded standard does, so that a field means what a browser sent:
    # split on `&` only, a field with no value dropped, `+` a space, an
    # invalid escape left as it is and bytes that are not UTF-8 replaced,
    # the first value of a repeated name the one that counts, a name with
    # brackets just a name.
    class Form
        def self.parse(raw)
            text = raw.to_s.dup.force_encoding(Encoding::UTF_8)
                      .scrub("�")
            fields = {}
            text.split("&").each do |pair|
                name, value = pair.split("=", 2)
                next if value.nil? || value.empty?

                (fields[unquote(name)] ||= []) << unquote(value)
            end
            new(fields)
        end

        def self.unquote(text)
            text.tr("+", " ").b.gsub(/%(\h\h)/n) { it[1, 2].hex.chr }
                .force_encoding(Encoding::UTF_8).scrub("�")
        end

        # name => every value, in the order sent.
        attr_reader :fields

        def initialize(fields) = @fields = fields

        # The first value of `name`, "" when there is none.
        def [](name) = get(name) || ""

        def get(name, default = nil) = @fields[name]&.first || default
    end
end
