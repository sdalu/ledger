# frozen_string_literal: true

# tls.rake -- this service's certificate, asked of an authority named
# by an address. Needs preflight.rake beside it, and tls_acme.rake for
# the "acme" protocol.
#
#   rake tls:cert            ask for a certificate, or keep a good one
#   rake tls:cert FORCE=1    ask again whatever is there
#   rake tls:root            what root an "own" authority serves
#   rake check:certificates  will it be accepted, and for how long
#
# NOTHING TO EDIT. The settings answer `tls` with a Hash, or with nil
# for a service that serves no TLS itself. Two protocols, named and
# never guessed from the address; one this file does not speak is
# refused:
#
#   tls: { ca:       "http://ca.example.com:4590",
#          protocol: "own",
#          root:     "sha256:<64 hex digits>" }
#
#   tls: { ca:        "https://acme-v02.api.letsencrypt.org/directory",
#          protocol:  "acme",
#          challenge: "http-01",            # or "tls-alpn-01"
#          terms:     true,                 # the CA's subscriber terms
#          contact:   "mailto:admin@example.com" }   # optional
#
# "own" is the three routes of tls_authority_routes.rb. `root` is the
# fingerprint of its root, and it is all that is trusted: the key
# never leaves this machine and a request holds nothing secret, so a
# certificate is kept only when it carries this service's key, the
# names asked for, and a chain to the pinned root. Someone in the path
# can refuse a certificate; they cannot supply one.
#
# "acme" is any RFC 8555 authority, Let's Encrypt among them, trusted
# the way a browser trusts it: through the system's roots, plus those
# in a `trust:` file for a private or test authority. tls_acme.rake
# says how each challenge is answered.
#
# The names are the addresses the service binds and the host names
# it permits, loopback left out: no authority vouches for "localhost".
# A `names:` list in the Hash replaces them.
#
# A new certificate is served after a restart, and not before:
#
#   rake tls:cert && rake server:restart

require "fileutils"
require "ipaddr"
require "json"
require "net/http"
require "openssl"
require "uri"

module TLS
    DIR  = LedgerViewer::Config.tls_dir.freeze
    KEY  = "#{DIR}/key.pem".freeze
    CERT = "#{DIR}/cert.pem".freeze
    ROOT = "#{DIR}/root.pem".freeze

    # Protocol name to the method that turns a request into a chain,
    # the leaf first.
    PROTOCOLS = { "own" => :own, "acme" => :acme }.freeze

    PIN = /\Asha256:\h{64}\z/

    PEM = /-----BEGIN CERTIFICATE-----.+?-----END CERTIFICATE-----/m

    # Renewed once less than this share of its life is left, so a
    # renewal that fails has that long to be noticed.
    MARGIN = 1.0 / 3

    module_function

    # [config, tls] or nil when the service serves no TLS itself.
    def settings
        config, = Preflight.settings(quiet: true)
        tls = config.tls if config.respond_to?(:tls)
        tls && [config, validated(tls)]
    end

    def validated(tls)
        problem = misconfigured(tls)
        abort("tls: #{problem}") if problem

        tls
    end

    def misconfigured(tls)
        protocol = tls[:protocol].to_s
        unless PROTOCOLS.key?(protocol)
            return "protocol #{protocol.inspect} is not one of " \
                   "#{PROTOCOLS.keys.join(", ")}."
        end
        return "ca must be an http or https address." unless
            URI(tls[:ca].to_s).is_a?(URI::HTTP)
        return ACME.misconfigured(tls) if protocol == "acme"
        return if tls[:root].to_s.match?(PIN)

        "root must be sha256: and 64 hex digits -- rake tls:root prints it."
    end

    # What the certificate must name, as strings, sorted. An address is
    # written the one way a certificate gives it back, so the two
    # compare.
    def names(config, tls)
        found = (tls[:names] || served(config)).map { canonical(it.to_s) }
        abort("tls: nothing to name -- every bind is loopback.") if
            found.empty?
        every = found.find { address(it)&.to_i&.zero? }
        if every
            abort("tls: #{every} is every address, which no certificate " \
                  "names -- bind the service's own, or list them in names:.")
        end

        found.uniq.sort
    end

    def canonical(name) = address(name)&.to_s || name.downcase

    def served(config)
        binds = config.bind.map { it.rpartition(":").first.delete("[]") }
        hosts = (config.permitted_hosts if config.respond_to?(:permitted_hosts))
        (binds + Array(hosts).filter_map { host(it) })
            .reject { it.empty? || local?(it) }
    end

    # A permitted host as a name to certify, or nil for an entry that
    # names no single host: a pattern, a network, or ".example.com",
    # which permits every name below it.
    def host(entry)
        case entry
        when IPAddr then entry.to_s if entry.to_range.one?
        when String then entry unless entry.start_with?(".")
        end
    end

    def local?(name)
        address(name)&.loopback? || name == "localhost" ||
            name.end_with?(".localhost")
    end

    def address(name)
        IPAddr.new(name)
    rescue IPAddr::Error
        nil
    end

    def request(key, names)
        csr = OpenSSL::X509::Request.new
        csr.subject    = OpenSSL::X509::Name.new([["CN", names.first]])
        csr.public_key = key
        csr.add_attribute(wanted(names))
        csr.sign(key, "SHA256")
    end

    # The names travel as a requested subjectAltName, the only place
    # an authority reads them from.
    def wanted(names)
        san = names.map { address(it) ? "IP:#{it}" : "DNS:#{it}" }
        factory = OpenSSL::X509::ExtensionFactory.new
        extension = factory.create_extension("subjectAltName", san.join(","))
        OpenSSL::X509::Attribute.new(
            "extReq",
            OpenSSL::ASN1::Set([OpenSSL::ASN1::Sequence([extension])])
        )
    end

    # The names a certificate carries, read from its ASN.1: tag 2 is
    # a host name, tag 7 an address.
    def names_of(cert)
        san = cert.extensions.find { it.oid == "subjectAltName" }
        return [] unless san

        OpenSSL::ASN1.decode(san.value_der).value.filter_map do |name|
            case name.tag
            when 2 then name.value.downcase
            when 7 then IPAddr.new_ntoh(name.value).to_s
            end
        end.sort
    end

    def fingerprint(cert)
        "sha256:#{OpenSSL::Digest::SHA256.hexdigest(cert.to_der)}"
    end

    def certificates(pem)
        pem.to_s.scan(PEM).map { OpenSSL::X509::Certificate.new(it) }
    end

    # What a chain must lead to. For "own", the pinned root as it was
    # stored beside the certificate, or nil when that is not the pin;
    # for "acme", the system's roots and those of the `trust:` file.
    def anchors(tls)
        store = OpenSSL::X509::Store.new
        return ACME.anchors(store, tls) if tls[:protocol].to_s == "acme"

        root = certificates(File.exist?(ROOT) ? File.read(ROOT) : "").first
        return nil unless root && fingerprint(root) == tls[:root]

        store.add_cert(root)
    end

    # The authority's root, whatever it is: the caller compares it
    # with the pin. Verification is off for this one fetch because
    # the pin is the check, and it is stronger than a chain.
    def fetch_root(tls)
        answer = call(tls, Net::HTTP::Get.new("/root.pem"))
        OpenSSL::X509::Certificate.new(answer.body)
    rescue OpenSSL::X509::CertificateError
        abort("tls: #{tls[:ca]}/root.pem is not a certificate.")
    end

    def pinned_root(tls)
        root = fetch_root(tls)
        return root if fingerprint(root) == tls[:root]

        abort("tls: the authority serves #{fingerprint(root)}\n" \
              "tls: the settings pin     #{tls[:root]}\n" \
              "Nothing was requested.")
    end

    # The root is stored beside the certificate as it is fetched, so
    # the chain is verified against the same root the pin approved.
    def own(tls, _names, csr)
        root = pinned_root(tls)
        post = Net::HTTP::Post.new("/sign")
        post.body = csr.to_pem
        post["content-type"] = "application/pkcs10"
        answer = call(tls, post)
        abort("tls: the authority refused -- #{answer.body.strip}") unless
            answer.is_a?(Net::HTTPOK)

        [certificates(answer.body), root]
    end

    def acme(tls, names, csr)
        [ACME.certificate(tls, names, csr), nil]
    rescue ACME::Refused => e
        abort("tls: the authority refused -- #{e.message}")
    rescue ACME::Unanswerable => e
        abort("tls: #{e.message}")
    rescue JSON::ParserError
        abort("tls: #{tls[:ca]} answered with something that is not ACME.")
    rescue *UNREACHABLE => e
        abort("tls: #{tls[:ca]} did not answer -- #{e.message}")
    end

    # What an authority that cannot be reached, or cannot be trusted
    # over https, raises.
    UNREACHABLE = [SystemCallError, Timeout::Error, SocketError, EOFError,
                   OpenSSL::SSL::SSLError].freeze

    def call(tls, message)
        uri = URI(tls[:ca].to_s)
        message.path.prepend(uri.path.chomp("/"))
        connection(uri).request(message)
    rescue *UNREACHABLE => e
        abort("tls: #{tls[:ca]} did not answer -- #{e.message}")
    end

    # The peer's certificate is not verified, over https either: what
    # comes back is checked against the pin, which no chain improves.
    def connection(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = http.read_timeout = 15
        return http unless uri.scheme == "https"

        http.use_ssl     = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        http
    end

    # Why a chain cannot be used, or nil. Every reason a client or the
    # server would have for refusing it, checked here first.
    def fault(chain, key, store, names)
        leaf = chain.first
        return "it is not a certificate" unless leaf
        return "it does not carry this service's key" unless
            leaf.check_private_key(key)
        return "its chain does not verify (#{store.error_string})" unless
            store.verify(leaf, chain.drop(1))

        missing = names - names_of(leaf)
        "it does not name #{missing.join(", ")}" unless missing.empty?
    end

    # Each file is written whole beside its place and moved in, the
    # key created closed, so no file is ever half written. The moves
    # are one per file, not one for the set: a run stopped between
    # them leaves a key that does not match the chain, which
    # check:certificates blocks on and the next tls:cert replaces.
    # The certificate file is the chain the server presents, the leaf
    # first.
    def install(key, chain, root)
        directory
        files = { KEY => key.to_pem, CERT => chain.map(&:to_pem).join }
        files[ROOT] = root.to_pem if root
        files.map { |file, pem| [file, staged(file, pem)] }
             .each { |file, temporary| File.rename(temporary, file) }
    end

    # The directory, closed to everyone else, its parent made if need be.
    def directory
        FileUtils.mkdir_p(File.dirname(DIR))
        Dir.mkdir(DIR, 0o700) unless File.directory?(DIR)
    end

    def staged(file, pem)
        temporary = "#{file}.new"
        FileUtils.rm_f(temporary)
        flags = File::WRONLY | File::CREAT | File::EXCL
        File.open(temporary, flags, 0o600) { it.write(pem) }
        temporary
    end

    # [key, chain] as they are on disk, or nil when either is missing
    # or unreadable.
    def installed
        return nil unless [KEY, CERT].all? { File.exist?(it) }

        chain = certificates(File.read(CERT))
        chain.empty? ? nil : [OpenSSL::PKey.read(File.read(KEY)), chain]
    rescue OpenSSL::OpenSSLError, SystemCallError
        nil
    end

    def renewal(cert)
        cert.not_after - ((cert.not_after - cert.not_before) * MARGIN)
    end

    def day(time) = time.utc.strftime("%Y-%m-%d")

    # True when what is installed needs no replacing.
    def good?(tls, names)
        key, chain = installed
        store = anchors(tls)
        return false unless chain && store

        fault(chain, key, store, names).nil? &&
            Time.now < renewal(chain.first)
    end

    def obtain(tls, names)
        key = OpenSSL::PKey::EC.generate("prime256v1")
        chain, root = send(PROTOCOLS.fetch(tls[:protocol].to_s), tls,
                           names, request(key, names))
        store = root ? OpenSSL::X509::Store.new.add_cert(root) : anchors(tls)
        problem = fault(chain, key, store, names)
        abort("tls: the certificate was not kept -- #{problem}.") if problem

        install(key, chain, root)
        chain.first
    end

    # The check:certificates lines; returns the blocking count.
    def report(tls, names)
        key, chain = installed
        unless chain
            return Preflight.item(:block, CERT, "missing or unreadable " \
                                                "-- run: rake tls:cert")
        end

        exposure + trust(tls, key, chain, names) + lifetime(chain.first)
    end

    # Starts fine and is still wrong: a key others can read, or one
    # in the repository.
    def exposure
        Preflight.item(:warn, KEY, "readable by others -- chmod 600") if
            File.stat(KEY).mode.anybits?(0o077)
        Preflight.item(:warn, KEY, "TRACKED -- git rm --cached #{KEY}") if
            Preflight.tracked?(KEY)
        0
    end

    def trust(tls, key, chain, names)
        again = "-- run: rake tls:cert"
        store = anchors(tls)
        unless store
            return Preflight.item(:block, ROOT, "not the pinned root #{again}")
        end

        problem = fault(chain, key, store, names)
        return Preflight.item(:block, CERT, "#{problem} #{again}") if problem

        Preflight.item(:ok, CERT, names_of(chain.first).join(", "))
    end

    def lifetime(cert)
        left = ((cert.not_after - Time.now) / 86_400).floor
        detail = "until #{day(cert.not_after)}, #{left} day(s)"
        return Preflight.item(:block, "expiry", "expired") if left.negative?
        return Preflight.item(:ok, "expiry", detail) if
            Time.now < renewal(cert)

        Preflight.item(:warn, "expiry", "#{detail} -- run: rake tls:cert")
    end
end

namespace :tls do
    desc "Ask the authority for this service's certificate"
    task :cert do
        config, tls = TLS.settings
        abort("tls: the settings name no authority.") unless tls

        names = TLS.names(config, tls)
        if ENV["FORCE"] != "1" && TLS.good?(tls, names)
            _, chain = TLS.installed
            puts "#{TLS::CERT} is good until " \
                 "#{TLS.day(chain.first.not_after)}; kept. FORCE=1 asks again."
            next
        end

        cert = TLS.obtain(tls, names)
        puts "#{TLS::CERT}: #{names.join(", ")}, until " \
             "#{TLS.day(cert.not_after)}.\n" \
             "A running service keeps the old one until: rake server:restart"
    end

    desc "Print the fingerprint of the root an own authority serves"
    task :root do
        config, = Preflight.settings(quiet: true)
        tls = config.tls if config.respond_to?(:tls)
        abort("tls: the settings name no own authority.") unless
            tls && tls[:ca] && tls[:protocol].to_s == "own"

        puts TLS.fingerprint(TLS.fetch_root(tls))
        puts "Compare it with what the authority itself prints " \
             "(rake check:root there),\nthen set it as tls root: " \
             "in the local settings."
    end
end

namespace :check do
    desc "The certificate: present, matching, vouched for, current"
    task :certificates do
        $stdout.sync = true
        Preflight.title("Certificate")
        config, tls = TLS.settings
        next Preflight.item(:info, "tls", "not served by this service") unless
            tls

        blocking = TLS.report(tls, TLS.names(config, tls))
        next unless blocking.positive?

        abort("\n#{blocking} blocking problem(s); it will not start, or " \
              "no client will accept it.")
    end
end
