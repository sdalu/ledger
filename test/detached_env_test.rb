# frozen_string_literal: true

require_relative "test_helper"
require "rake"

# The environment a detached session (rake server:start TMUX=name) is
# started with: what was set before bundler loaded, plus what was set
# since, less bundler's own variables.
class DetachedEnvTest < Minitest::Test
    ROOT = File.expand_path("..", __dir__)

    def setup
        @saved = ENV.to_h
        return if defined?(Detached)

        %w[preflight server].each { load File.join(ROOT, "rakelib/#{it}.rake") }
    end

    def teardown
        ENV.replace(@saved)
    end

    # rake turns DEBUG=1 into ENV["DEBUG"] after bundler took its copy
    # of the environment: the session must still see it.
    def test_a_variable_set_after_bundler_loaded_reaches_the_session
        ENV["LEDGER_DETACHED_PROBE"] = "1"

        assert_equal "1", Detached.clean_env["LEDGER_DETACHED_PROBE"]
    end

    # A lockfile in the session's environment would make another
    # project's bundle rewrite that lockfile.
    def test_bundler_variables_do_not_reach_the_session
        ENV["BUNDLE_LOCKFILE"] = "/elsewhere/Gemfile.lock"
        ENV["BUNDLE_GEMFILE"] = "/elsewhere/Gemfile"
        env = Detached.clean_env

        refute env.key?("BUNDLE_LOCKFILE")
        refute env.key?("BUNDLE_GEMFILE")
        refute_match %r{bundler/setup}, env.fetch("RUBYOPT", "")
    end
end
