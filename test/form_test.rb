# frozen_string_literal: true

require "test_helper"

# A posted body is read as a urlencoded form: the expected fields are
# fixed literals.
class FormTest < Minitest::Test
    R = "\u{FFFD}"

    # Each body with the fields a urlencoded reader gives it: values
    # in order per name, a field without "=" or with an empty value
    # dropped, ";" not a separator, invalid UTF-8 replaced by U+FFFD.
    EXPECTED = {
        "a=1&b=2" => { "a" => ["1"], "b" => ["2"] },
        "a=1&a=2" => { "a" => %w[1 2] },
        "a=&b=2" => { "b" => ["2"] },
        "a&b=2" => { "b" => ["2"] },
        "=x" => { "" => ["x"] },
        "a=%41%2B+b" => { "a" => ["A+ b"] },
        "a=%zz%4" => { "a" => ["%zz%4"] },
        "a=%C3%A9&b=\u00e9" => { "a" => ["\u00e9"], "b" => ["\u00e9"] },
        "a=%FF&b=%ED%A0%80&c=%C3" => { "a" => [R], "b" => [R * 3],
                                       "c" => [R] },
        "x[y]=1&x[z]=2" => { "x[y]" => ["1"], "x[z]" => ["2"] },
        "a=1;b=2" => { "a" => ["1;b=2"] },
        "a=1&&b=2" => { "a" => ["1"], "b" => ["2"] },
        "a=%E2%82" => { "a" => [R] },
        "t=a%0D%0Ab" => { "t" => ["a\r\nb"] },
        "a=%2526" => { "a" => ["%26"] }
    }.freeze

    def test_a_body_is_read_as_a_urlencoded_form
        EXPECTED.each do |body, fields|
            assert_equal fields, LedgerViewer::Form.parse(body).fields,
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
end
