# frozen_string_literal: true

require "rake"
require "test_helper"

# The machine's own files -- the local config and the certificate
# directory -- live outside the checkout, and nothing here reads or
# writes the real ones.
class MachineFilesTest < Minitest::Test
    ROOT = File.expand_path("..", __dir__)
    HOME_DIR = File.join(Dir.home, ".config", "ledger-viewer")

    def setup = @dir = Dir.mktmpdir("machine", SANDBOX)

    # 1. The local file is under ~/.config unless the variable names
    # another, and the checkout's config/app.local.rb is never read.
    def test_the_local_file_is_outside_the_checkout
        saved = ENV.delete("LEDGER_VIEWER_LOCAL")

        assert_equal File.join(HOME_DIR, "app.local.rb"),
                     LedgerViewer::Config.local_file(nil)
    ensure
        ENV["LEDGER_VIEWER_LOCAL"] = saved
    end

    def test_the_checkouts_own_local_file_is_unread
        FileUtils.mkdir_p(File.join(@dir, "config"))
        FileUtils.cp(File.join(ROOT, "config/app.rb"),
                     File.join(@dir, "config"))
        File.write(File.join(@dir, "config/app.local.rb"), "{ typo: 1 }")
        local = File.join(@dir, "elsewhere.rb")
        File.write(local, %({ session_secret: "#{"s" * 32}" }))

        assert_equal "s" * 32,
                     LedgerViewer::Config.load(root: @dir, local:)
                                         .session_secret
    end

    # 2. tls_dir defaults under ~/.config, is overridable, and config.rb
    # reads it for the listeners (puma.rb asks the same Config).
    def test_tls_dir_is_a_setting_read_by_the_config
        shared = File.join(ROOT, "config/app.rb")
        none = File.join(@dir, "none.rb")

        assert_equal File.join(HOME_DIR, "tls"),
                     LedgerViewer::Config.tls_dir(shared:, local: none)

        File.write(none, %({ tls_dir: "#{@dir}/mine" }))

        assert_equal "#{@dir}/mine",
                     LedgerViewer::Config.tls_dir(shared:, local: none)
    end

    # 3. rake tls makes the directory closed to others and the key 600.
    def test_tls_install_makes_the_directory_closed_and_the_key_private
        load_rake_files
        dir = TLS::DIR
        key = OpenSSL::PKey::EC.generate("prime256v1")

        assert_equal File.join(SANDBOX, "tls"), dir
        TLS.install(key, [self_signed(key)], nil)

        assert_equal 0o700, File.stat(dir).mode & 0o777
        assert_equal 0o600, File.stat(TLS::KEY).mode & 0o777
    end

    # 4. The example and the pre-flight name the new place.
    def test_the_example_and_the_preflight_name_the_new_place
        example = File.read(File.join(ROOT, "config/app.local.rb.example"))

        assert_includes example, "~/.config/ledger-viewer/app.local.rb"
        refute_includes File.read(File.join(ROOT, ".gitignore")),
                        "app.local.rb"
        load_rake_files
        saved = ENV.delete("LEDGER_VIEWER_LOCAL")

        assert_equal File.join(HOME_DIR, "app.local.rb"),
                     Preflight.local_place("config/app.local.rb.example")
    ensure
        ENV["LEDGER_VIEWER_LOCAL"] = saved
    end

    # 5. The suite itself is pointed at the sandbox.
    def test_the_suite_reads_no_file_under_the_home_config
        assert ENV.fetch("LEDGER_VIEWER_LOCAL").start_with?(SANDBOX)
        assert LedgerViewer::Config.tls_dir.start_with?(SANDBOX)
    end

    private

    def load_rake_files
        return if defined?(TLS)

        %w[preflight tls].each { load File.join(ROOT, "rakelib/#{it}.rake") }
    end

    def self_signed(key)
        cert = OpenSSL::X509::Certificate.new
        cert.version = 2
        cert.serial = 1
        cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=test")
        cert.public_key = key
        cert.not_before = Time.now - 60
        cert.not_after = Time.now + 3600
        cert.sign(key, "SHA256")
    end
end
