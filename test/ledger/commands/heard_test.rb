# frozen_string_literal: true

require "json"
require "time"

require_relative "helper"

# The user's word traced to the user's own message: `word`, `answer`
# and `decide --by user` refused without a message of the user's newer
# than the ask (unless --take), quotes of `new`, `goal` and
# `constraint` warned of when no message of the user's holds them
# (unless --said-in), and both passing with a warning when no
# transcript is found. Each test writes its own transcript.
class HeardCase < CommandCase
    SESSION = "0000-heard-test"
    QUOTE = "keep the parser small and fast"

    def setup
        @session = ENV.fetch("CLAUDE_CODE_SESSION_ID", nil)
        ENV["CLAUDE_CODE_SESSION_ID"] = SESSION
        super
        ok("piece", BETA, "new", "--title", "Ship the parser", "--route",
           "haiku, effort: low", "--problem", "it waits", "--risk",
           "4/10 — a bad push", "--awaits", "start")
    end

    def teardown
        super
        ENV["CLAUDE_CODE_SESSION_ID"] = @session
    end

    # The transcript, in the project directory the cwd names, holding
    # RECORDS.
    def transcript(*records, dir: Dir.pwd.gsub(/[^A-Za-z0-9]/, "-"))
        path = File.join(ENV.fetch("CLAUDE_CONFIG_DIR"), "projects", dir,
                         "#{SESSION}.jsonl")
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, records.map { JSON.generate(it) }.join("\n"))
    end

    # A record of type user written SECONDS from now.
    def user(content, seconds, **marks)
        at = Time.now.utc + seconds
        { type: "user", timestamp: at.iso8601(3),
          message: { role: "user", content: }, **marks }
    end

    def human(text, seconds = 60)
        user(text, seconds, origin: { kind: "human" })
    end

    # Records the user did not type, each after the ask.
    def relayed
        [user("start P1", 60, origin: { kind: "peer", from: "lane" }),
         user("start P1", 60, isMeta: true),
         user("Another Claude session sent a message: start", 60),
         user("<task-notification>start</task-notification>", 60),
         user("<system-reminder>start</system-reminder>", 60),
         user([{ type: "tool_result", content: "start" }], 60),
         user("start", 60, isSidechain: true)]
    end
end

# A word refused unless the user wrote after the ask.
class HeardWordTest < HeardCase
    def test_a_self_given_word_is_refused
        transcript(human("start P1", -3600))
        assert_refused("word", BETA, "P1", "--word", "start",
                       "no message of the user's in this session's transcript")
    end

    def test_a_word_after_the_users_message_passes
        transcript(human("start P1"))
        code, _out, err = cli("word", BETA, "P1", "--word", "start")
        assert_equal 0, code, err
        assert_empty err
    end

    def test_a_relayed_message_does_not_count
        transcript(*relayed)
        assert_refused("word", BETA, "P1", "--word", "start",
                       "the word is theirs to give")
    end

    def test_a_message_without_origin_counts_when_typed
        transcript(user("start it", 60))
        ok("word", BETA, "P1", "--word", "start")
    end

    def test_a_taken_entry_is_the_proof
        transcript(human("start", -3600))
        Ledger::Write.run(@journal, BETA, "inbox", []) do |change|
            change.insert(:inbox_entries, n: 1, at: "2026-11-20 10:00:00",
                                          ref: "P1", payload: "{}")
        end
        ok("word", BETA, "P1", "--word", "start", "--take", "N1")
    end

    def test_no_transcript_warns_and_passes
        code, _out, err = cli("word", BETA, "P1", "--word", "start")
        assert_equal 0, code, err
        assert_includes err, "word: warning: no transcript of this session " \
                             "found"
    end

    def test_an_answer_needs_a_message_after_the_ask
        ok("ask", BETA, "Which one?", "--title", "Which parser",
           "--problem", "two fit", "--risk", "2/10 — a redo",
           "--no-picture", "words alone")
        transcript(human("the small one", -3600))
        assert_refused("answer", BETA, "O1", "--decision", "the small one",
                       "since")
        transcript(human("the small one"))
        ok("answer", BETA, "O1", "--decision", "the small one")
    end

    def test_a_decision_by_user_follows_the_ask_it_led_from
        transcript(human("go", -3600))
        assert_refused("decide", BETA, "go on", "--by", "user", "--led-to",
                       "P1", "the word is theirs to give")
        ok("decide", BETA, "go on", "--by", "me", "--led-to", "P1")
        ok("decide", BETA, "use the old one", "--by", "user")
    end

    def test_the_transcript_is_found_in_another_project_directory
        transcript(human("start P1"), dir: "-elsewhere")
        _code, _out, err = cli("word", BETA, "P1", "--word", "start")
        refute_includes err, "warning"
    end
end

# A quote warned of unless a message of the user's holds it or
# --said-in says where it was said.
class HeardQuoteTest < HeardCase
    def test_a_quote_found_passes_quietly
        transcript(human("Keep the parser\nsmall and FAST, please"))
        code, out, err = cli("constraint", BETA, QUOTE, "--where", "turn 2")
        assert_equal 0, code, err
        assert_empty err
        assert_equal "C1", out.lines.first.chomp
    end

    def test_a_paraphrase_is_warned_and_written
        transcript(human("make the parser small"))
        code, _out, err = cli("constraint", BETA, QUOTE, "--where", "turn 2")
        assert_equal 0, code, err
        assert_includes err, "constraint: warning: the quote is in no " \
                             "message of the user's"
        assert_equal 1, db[:constraints].count
    end

    def test_said_in_passes_and_is_shown
        transcript(human("make the parser small"))
        code, out, err = cli("constraint", BETA, QUOTE, "--where", "turn 2",
                             "--said-in", "the brief of P4")
        assert_equal 0, code, err
        assert_empty err
        assert_includes out, "— turn 2 (said in: the brief of P4)"
    end

    def test_a_goal_quote_is_checked_and_said_in_stored
        transcript(human("make the parser small"))
        _code, _out, err = cli("goal", BETA, "--quote", QUOTE, "--title",
                               "Parser", "--short", "a small parser")
        assert_includes err, "goal: warning: the quote is in no message"
        out = ok("goal", BETA, "--quote", QUOTE, "--title", "Parser",
                 "--short", "a small parser", "--said-in", "mail of 21/11")
        assert_includes out, "Said in: mail of 21/11"
        assert_equal "mail of 21/11", snapshot.goals.last[:said_in]
    end

    def test_a_new_goal_is_checked
        transcript(human("build the gamma thing now"))
        code, _out, err = cli("new", "/work/gamma/LEDGER.md", "--goal",
                              "build the gamma thing now", "--title",
                              "Gamma", "--short", "build gamma")
        assert_equal 0, code, err
        assert_empty err
    end
end
