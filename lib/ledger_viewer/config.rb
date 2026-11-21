# frozen_string_literal: true

module LedgerViewer
    # What the viewer is told at boot, from two files read once:
    # config/app.rb, tracked, what is true of the program; and
    # ~/.config/ledger-viewer/app.local.rb, outside the checkout, what is
    # true of this machine (its secrets never sit in a tree that is
    # pushed). Both are plain Ruby ending in a Hash; the local file is
    # read second and wins on any key. $LEDGER_VIEWER_LOCAL names another
    # local file (a sandbox), honoured here so that every way of starting
    # agrees.
    class Config
        ROOT = File.expand_path("../..", __dir__)

        # The least length of the session secret.
        SECRET = 32

        # A key given that nothing reads is refused: a typo is not
        # silent.
        KEYS = %i[bind session_days session_secret tls tls_dir lan].freeze

        # host:port, the host a name, an IPv4 address or [IPv6].
        ADDRESS = %r{\A(?:[^\s:/\[\]]+|\[[0-9a-f:]+\]):\d+\z}i

        # The local file when $LEDGER_VIEWER_LOCAL is unset.
        LOCAL = "~/.config/ledger-viewer/app.local.rb"

        def self.load(root: ROOT, shared: nil, local: nil)
            new(root:, **evaluate(shared_file(root, shared)),
                **evaluate(local_file(local)))
        end

        # The tls_dir setting alone, for rakelib/tls.rake, which names
        # its files when it is loaded, before any task needs the rest of
        # the settings: a local file not written yet is not an error here.
        def self.tls_dir(root: ROOT, shared: nil, local: nil)
            file = local_file(local)
            settings = evaluate(shared_file(root, shared))
            settings.merge!(evaluate(file)) if File.exist?(file)
            File.expand_path(settings.fetch(:tls_dir), root)
        end

        def self.shared_file(root, given)
            given || File.join(root, "config", "app.rb")
        end

        def self.local_file(given)
            File.expand_path(given || ENV.fetch("LEDGER_VIEWER_LOCAL", nil) ||
                             LOCAL)
        end

        # Evaluated, not parsed: files the owner of the host writes, on
        # the footing of the code they configure, read once at boot.
        def self.evaluate(file)
            return {} unless File.exist?(file)

            # rubocop:disable-next Security/Eval
            settings = eval(File.read(file), TOPLEVEL_BINDING, file)
            return settings.transform_keys(&:to_sym) if settings.is_a?(Hash)

            raise ConfigError, "#{file}: does not end in a Hash"
        end

        # bind: host:port, as written or as tcp://host:port.
        attr_reader :bind, :session_secret, :session_days, :tls, :tls_dir,
                    :lan

        def initialize(root: ROOT, **settings)
            unknown = settings.keys - KEYS
            raise ConfigError, "not a setting: #{unknown.join(", ")}" unless
                unknown.empty?

            @bind = binds(settings.fetch(:bind))
            @session_secret = secret(settings[:session_secret])
            @lan = Lan.networks(settings[:lan])
            limits(settings, root)
            freeze
        end

        # The page's stylesheet and script, served from public/.
        def stylesheet = File.join(ROOT, "public", "viewer.css")

        def script = File.join(ROOT, "public", "viewer.js")

        # Where rakelib/tls.rake leaves the certificate and key.
        def tls_cert = File.join(@tls_dir, "cert.pem")

        def tls_key = File.join(@tls_dir, "key.pem")

        # What puma is asked to listen on: ssl:// with the certificate
        # when tls is set, tcp:// when it is nil.
        def listeners
            return @bind.map { "tcp://#{it}" } unless @tls

            @bind.map { "ssl://#{it}?cert=#{tls_cert}&key=#{tls_key}" }
        end

        # The names the Host header may carry: those bound, and localhost.
        def permitted_hosts
            (@bind.map { host_of(it) } + %w[localhost .localhost]).uniq
        end

        private

        # The numbers, and tls: nil, or what rakelib/tls.rake reads, and where
        # it leaves the files.
        def limits(settings, root)
            @tls = tls_of(settings[:tls])
            @tls_dir = File.expand_path(settings.fetch(:tls_dir), root)
            @session_days = positive(:session_days, settings)
        end

        def host_of(address)
            address.rpartition(":").first.delete_prefix("[").delete_suffix("]")
        end

        # host:port each, tcp only: a socket would need its own trust
        # rules, which a later piece owns.
        def binds(given)
            list = Array(given).map { it.to_s.delete_prefix("tcp://") }
            raise ConfigError, "bind: an address to listen on" if list.empty?

            bad = list.grep_v(ADDRESS)
            return list.freeze if bad.empty?

            raise ConfigError, "bind: host:port or tcp://host:port, " \
                               "not #{bad.join(", ")}"
        end

        # nil, or the Hash rakelib/tls.rake reads (ca:, protocol:, root:,
        # names: optional); that file refuses what it cannot use.
        def tls_of(given)
            return if given.nil?
            return given.transform_keys(&:to_sym).freeze if given.is_a?(Hash)

            raise ConfigError, "tls: nil, or a Hash (ca:, protocol:, root:)"
        end

        def secret(given)
            return given.to_s if given.to_s.length >= SECRET

            raise ConfigError, "session_secret: #{SECRET} characters at least"
        end

        def positive(key, settings)
            value = Integer(settings.fetch(key))
            return value if value.positive?

            raise ConfigError, "#{key}: a number above 0"
        end
    end
end
