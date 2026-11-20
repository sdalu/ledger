# frozen_string_literal: true

require "test_helper"

# What a deployment may say about itself, and what the example promises.
class ConfigTest < Minitest::Test
    ROOT = File.expand_path("..", __dir__)

    def setup = @dir = Dir.mktmpdir("config", SANDBOX)

    def config(**given)
        LedgerViewer::Config.new(
            root: @dir, bind: "tcp://127.0.0.1:4590", ledger_py: "e.py",
            python: "python3", dump_timeout: 5, store: "data/v.json",
            session_days: 1, roots: ["r"], session_secret: "s" * 32,
            tls_dir: "tls", **given
        )
    end

    def test_the_shared_file_and_the_example_read_as_one_config
        local = File.join(ROOT, "config/app.local.rb.example")
        loaded = LedgerViewer::Config.load(root: ROOT, local:)

        assert_equal ["127.0.0.1:4590"], loaded.bind
        assert_equal %w[127.0.0.1 localhost .localhost],
                     loaded.permitted_hosts
    end

    # The pre-flight blocks on a key the example sets and the local file
    # omits, and warns on one the example never mentions: both only work
    # if every key is one the loader reads.
    def test_every_key_in_both_files_is_one_the_loader_reads
        %w[config/app.rb config/app.local.rb.example].each do |file|
            keys = Object.new.instance_eval(File.read(File.join(ROOT, file)),
                                            file, 1).keys
            assert_empty keys - LedgerViewer::Config::KEYS, file
        end
    end

    def test_the_two_files_together_set_every_key
        keys = %w[config/app.rb config/app.local.rb.example].flat_map do |file|
            Object.new.instance_eval(File.read(File.join(ROOT, file)),
                                     file, 1).keys
        end

        assert_empty LedgerViewer::Config::KEYS - keys
    end

    def test_tls_is_nil_or_a_hash_and_puma_listens_accordingly
        assert_nil config.tls
        assert_equal ["tcp://127.0.0.1:4590"], config.listeners

        tls = { ca: "http://ca.example.com:4580", protocol: "own",
                root: "sha256:#{"0" * 64}" }
        secured = config(tls:)

        assert_equal tls, secured.tls
        assert_equal ["ssl://127.0.0.1:4590" \
                      "?cert=#{@dir}/tls/cert.pem&key=#{@dir}/tls/key.pem"],
                     secured.listeners
        assert_raises(LedgerViewer::ConfigError) { config(tls: "yes") }
    end

    def test_a_setting_nothing_reads_is_refused
        assert_raises(LedgerViewer::ConfigError) { config(typo: 1) }
    end

    def test_a_short_session_secret_is_refused
        assert_raises(LedgerViewer::ConfigError) do
            config(session_secret: "short")
        end
    end

    def test_a_socket_is_refused_for_now
        assert_raises(LedgerViewer::ConfigError) do
            config(bind: "unix:///tmp/v.sock")
        end
    end

    def test_the_local_file_wins_and_a_non_hash_is_refused
        path = File.join(@dir, "local.rb")
        File.write(path, "42")

        assert_raises(LedgerViewer::ConfigError) do
            LedgerViewer::Config.load(root: ROOT, local: path)
        end
    end

    def test_both_modes_together_are_refused
        ENV["DEBUG"] = ENV["PRODUCTION"] = "1"

        assert_raises(LedgerViewer::ModeError) { LedgerViewer.check_mode! }
    ensure
        %w[DEBUG PRODUCTION].each { ENV.delete(it) }
    end
end
