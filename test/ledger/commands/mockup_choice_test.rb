# frozen_string_literal: true

require_relative "mockup_test"

# What the `mockup --choice` tests share: O2, a question of three options.
class ChoiceCase < MockupCase
    def setup
        super
        ok("ask", BETA, "Which layout wins?", "--title", "Layout choice",
           "--problem", "the page is cramped", "--risk", "2/10 — a redraw",
           "--choices", "A = wide | B = narrow | C = tall",
           "--recommend", "A, roomier", "--no-picture", "words alone")
    end

    def place(label, name, *)
        ok("mockup", BETA, file(name), "--question", "O2", "--choice", label,
           *)
    end

    def pictures
        db[:question_choices].order(:position).select_map(%i[label picture])
    end

    def warning
        _, out, = cli("check", "--peek", BETA)
        out.lines(chomp: true).grep(/ pictures-options/).first
    end
end

# `mockup --question O<n> --choice LABEL`: a picture for one option of a
# question, replaced, refused on an unknown label, gone with a dropped
# option, shown by `show`.
class MockupChoiceTest < ChoiceCase
    def test_a_picture_is_placed_as_an_options_own
        out = place("A", "wide.png")

        assert_equal [["A", "wide.png"], ["B", nil], ["C", nil]], pictures
        assert_equal ["placed wide.png"], out.lines(chomp: true).first(1)
        assert_empty db[:question_pictures].all
    end

    def test_the_event_names_the_option
        place("B", "narrow.png")

        assert_equal "placed narrow.png for O2 option B",
                     db[:events].order(:id).last[:summary]
    end

    def test_the_label_is_folded
        place("  b ", "narrow.png")

        assert_equal "narrow.png", pictures[1].last
    end

    def test_a_second_picture_is_refused_without_replace
        place("A", "wide.png")

        assert_refused("mockup", BETA, file("wider.png"), "--question", "O2",
                       "--choice", "A",
                       "A has its picture (wide.png); add --replace to swap it")
    end

    def test_replace_swaps_the_picture
        place("A", "wide.png")
        place("A", "wider.png", "--replace")

        assert_equal "wider.png", pictures.first.last
    end

    def test_an_unknown_label_is_refused_naming_the_labels
        assert_refused("mockup", BETA, file("x.png"), "--question", "O2",
                       "--choice", "Z",
                       "O2 has no option Z; its labels: A, B, C")
    end

    def test_a_question_without_choices_is_refused
        assert_refused("mockup", BETA, file("x.png"), "--question", "O1",
                       "--choice", "A", "O1 has no `choices:`")
    end

    def test_one_picture_not_several
        assert_refused("mockup", BETA, file("x.png"), file("y.png"),
                       "--question", "O2", "--choice", "A",
                       "--choice places one picture, not 2")
    end

    def test_choice_is_not_for_a_piece
        assert_refused("mockup", BETA, file("x.png"), "--piece", "P1",
                       "--before", "--choice", "A",
                       "--choice is for --question, not --piece")
    end

    def test_dropping_the_option_removes_its_picture_link
        place("C", "tall.png")
        ok("choice", BETA, "O2", "--drop", "C")

        assert_equal [["A", nil], ["B", nil]], pictures
        assert_nil db[:question_choices].exclude(picture: nil).first
    end

    def test_show_prints_the_picture_after_its_option
        place("A", "wide.png")

        assert_includes markdown,
                        "— choices: A = wide — picture: wide.png | " \
                        "B = narrow | C = tall"
    end

    def test_show_json_carries_the_picture
        place("A", "wide.png")
        json = JSON.parse(ok("show", BETA, "--json"))
        choices = json["questions"].find { it["id"] == "O2" }["choices"]

        assert_equal(["wide.png", nil, nil], choices.map { it["picture"] })
    end
end

# The pictures-options warning: a partial set of option pictures.
class OptionPicturesCheckTest < ChoiceCase
    def test_a_partial_set_warns_naming_the_options_without
        place("B", "narrow.png")

        assert_equal "warn pictures-options -- O2: no picture for options " \
                     "A, C", warning
    end

    def test_none_or_all_do_not_warn
        assert_equal "ok   pictures-options", warning
        %w[A B C].each { place(it, "#{it}.png") }

        assert_equal "ok   pictures-options", warning
    end

    def test_the_warning_never_fails_the_check_or_final
        place("B", "narrow.png")

        assert_equal 0, cli("check", "--peek", BETA).first
        _, out, = cli("check", "--peek", "--final", BETA)
        refute_match(/FAIL pictures-options/, out)
    end

    def test_a_write_is_not_refused_for_the_warning
        place("B", "narrow.png")

        ok("choice", BETA, "O2", "--add", "D = other")
    end
end
