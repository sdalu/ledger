# frozen_string_literal: true

require "open3"

# A ledger of the engine's own making under the viewer's roots, for the
# tests of its page and of its pictures.
module LedgerFixture
    SCRIPTS = File.expand_path("../../../scripts", __dir__)
    RENDER = File.expand_path("python_render.py", __dir__)

    def setup
        super
        @ledger = File.join(@dir, "roots/gamma/.claude/LEDGER.md")
        FileUtils.mkdir_p([File.join(@dir, "roots/gamma/.git"), mockups])
        engine("new", @ledger, "--goal", "port the parser to C23",
               "--title", "Port the parser", "--short", "port the parser",
               "--date", "2026-11-19")
        engine("ask", @ledger, *QUESTION)
        @lid = Digest::SHA1.hexdigest(@ledger)[0, 10]
    end

    QUESTION = ["--title", "Which one", "which?", "--problem", "two",
                "--risk", "5/10 — meh", "--choices", "A = one | B = two",
                "--recommend", "A, simple", "--no-picture", "test"].freeze

    def mockups = File.join(File.dirname(@ledger), "mockups")

    def engine(*)
        out, status = Open3.capture2e(
            "python3", File.join(SCRIPTS, "ledger.py"), *
        )

        assert_predicate status, :success?, out
    end

    # A file in the ledger's folder of pictures.
    def picture(name, body = "<svg/>")
        path = File.join(mockups, name)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, body)
        path
    end

    # The two policies the Python viewer sends: {"page" =>, "mockup" =>}.
    def python_csp
        out, = Open3.capture2("python3", RENDER, "csp")
        JSON.parse(out)
    end
end
