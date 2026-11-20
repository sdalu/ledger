# frozen_string_literal: true

require "test_helper"
require "open3"

# A posted body is read as Python's parse_qs reads it, and an inbox line
# is written as json.dumps writes it: the Python viewer's files and the
# engine's reading of them are the reference.
class FormTest < Minitest::Test
    BODIES = [
        "a=1&b=2", "a=1&a=2", "a=&b=2", "a&b=2", "=x", "a=%41%2B+b",
        "a=%zz%4", "a=%C3%A9&b=é", "a=%FF&b=%ED%A0%80&c=%C3", "x[y]=1&x[z]=2",
        "a=1;b=2", "a=1&&b=2", "a=%E2%82", "t=a%0D%0Ab", "a=%2526"
    ].freeze

    PYTHON = <<~PY
        import json, sys
        from urllib.parse import parse_qs
        out = []
        for hexed in sys.argv[1:]:
            raw = bytes.fromhex(hexed).decode("utf-8", "replace")
            out.append(parse_qs(raw))
        print(json.dumps(out))
    PY

    def test_a_body_is_read_as_parse_qs_reads_it
        out, status = Open3.capture2("python3", "-I", "-c", PYTHON,
                                     *BODIES.map { it.b.unpack1("H*") })

        assert_predicate status, :success?
        expected = JSON.parse(out)
        BODIES.each_with_index do |body, at|
            assert_equal expected[at], LedgerViewer::Form.parse(body).fields,
                         body.inspect
        end
    end

    def test_a_missing_field_is_empty_and_the_first_value_counts
        form = LedgerViewer::Form.parse("a=1&a=2&b=")

        assert_equal "1", form["a"]
        assert_equal "", form["b"]
        assert_nil form.get("b")
        assert_equal "d", form.get("b", "d")
    end

    VALUES = [
        { "id" => "N1", "ref" => nil,
          "text" => "a\tb\n\"c\"\\ \u0001 \u007f \u2028 é 😀 / \u001f" },
        { "order" => %w[P1 P2], "picks" => { "S1" => "A = x" }, "n" => [] }
    ].freeze

    def test_a_line_is_written_as_json_dumps_writes_it
        script = "import json, sys; " \
                 "print(json.dumps(json.loads(sys.argv[1]), " \
                 "ensure_ascii=False))"
        VALUES.each do |value|
            out, = Open3.capture2("python3", "-I", "-c", script,
                                  JSON.generate(value))

            assert_equal out.chomp, LedgerViewer::PyJson.dump(value)
        end
    end
end
