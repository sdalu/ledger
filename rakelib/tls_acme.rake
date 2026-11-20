# frozen_string_literal: true

# tls_acme.rake -- the "acme" protocol of tls.rake (RFC 8555), on the
# standard library alone. No tasks of its own: tls:cert calls
# ACME.certificate. Drop it in rakelib/ beside tls.rake.
#
# THE SERVICE ANSWERS THE CHALLENGE ITSELF, by one of two methods,
# named by `challenge:` in the tls settings:
#
#   http-01      the authority fetches
#                http://<name>/.well-known/acme-challenge/<token>.
#                This task writes the answer under config/tls/challenge/
#                and the RUNNING service serves it, through
#                tls_challenge_routes.rb on a plain-HTTP bind of port 80.
#                Renewal keeps the service up.
#
#   tls-alpn-01  the authority opens TLS on port 443 asking for the
#                "acme-tls/1" protocol (RFC 8737). Puma cannot answer
#                that, so this task does, for the seconds the check
#                takes, and port 443 must be FREE: stop the service
#                first, start it after.
#
# `port:` moves the challenge off 80 or 443, which only a test
# authority (pebble) does: a real one always uses those two.
#
# `terms: true` is the deployment agreeing to the authority's
# subscriber terms, which its directory names. Nothing agrees for it.
#
# The account key is config/tls/account.pem, made on first use and
# kept: an authority counts its limits per account.

require "fileutils"
require "ipaddr"
require "json"
require "net/http"
require "openssl"
require "socket"
require "uri"

module ACME
    ACCOUNT    = "#{TLS::DIR}/account.pem".freeze
    CHALLENGES = "#{TLS::DIR}/challenge".freeze
    METHODS    = %w[http-01 tls-alpn-01].freeze

    # How long one order may take, from its creation to the
    # certificate, every wait for the authority included.
    WAIT = 120

    # An answer from the authority that ends the order: its own
    # problem document, worded as it sent it.
    class Refused < StandardError; end

    # This machine cannot answer a check: the port is taken, or not
    # this user's to bind. Nothing was asked of the authority.
    class Unanswerable < StandardError; end

    module_function

    def misconfigured(tls)
        unless METHODS.include?(tls[:challenge].to_s)
            return "challenge must be one of #{METHODS.join(", ")}."
        end
        return "ca must be an https address." unless
            URI(tls[:ca].to_s).is_a?(URI::HTTPS)
        return "trust: #{tls[:trust]} does not exist." if
            tls[:trust] && !File.file?(tls[:trust].to_s)
        return if tls[:terms] == true

        "terms: true, the agreement to the authority's terms, is not given."
    end

    def anchors(store, tls)
        store.set_default_paths
        return store unless tls[:trust]

        TLS.certificates(File.read(tls[:trust])).each { store.add_cert(it) }
        store
    end

    # An authority's problem document (RFC 7807) as one line: its type,
    # its words, and those of each name it failed on.
    def problem(document)
        document ||= {}
        type = document["type"].to_s.sub("urn:ietf:params:acme:error:", "")
        details = (document["subproblems"] || []).map { it["detail"] }
        [type, document["detail"], *details].compact.join(" -- ")
    end

    # base64url without padding, as every field of a request is.
    def b64(bytes) = [bytes].pack("m0").tr("+/", "-_").delete("=")

    def account_key
        return OpenSSL::PKey.read(File.read(ACCOUNT)) if File.exist?(ACCOUNT)

        key = OpenSSL::PKey::EC.generate("prime256v1")
        TLS.directory
        File.rename(TLS.staged(ACCOUNT, key.to_pem), ACCOUNT)
        key
    end

    def identifier(name)
        { type: TLS.address(name) ? "ip" : "dns", value: name }
    end

    # The chain, the leaf first.
    def certificate(tls, names, csr)
        session = Session.new(tls, account_key)
        session.register(tls)
        order, url = session.order(names.map { identifier(it) })
        Challenge.answer(session, tls, order.fetch("authorizations"))
        TLS.certificates(session.finish(order, url, csr))
    end

    # The account's side of the conversation: every request signed with
    # its key (JWS, ES256), each carrying the nonce the last answer gave.
    class Session
        # A nonce the authority refuses is retried with the one its refusal
        # carries; an authority may refuse some on purpose.
        RETRIES = 10

        def initialize(tls, key)
            @key  = key
            @http = connect(URI(tls[:ca]), ACME.anchors(OpenSSL::X509::Store.new,
                                                        tls))
            @directory = JSON.parse(get(tls[:ca]).body)
            @nonce = nil
            @kid   = nil
            @deadline = nil
        end

        def register(tls)
            terms = { termsOfServiceAgreed: true }
            terms[:contact] = [tls[:contact]] if tls[:contact]
            @kid = post(@directory.fetch("newAccount"), terms, jwk: true)
                   .fetch("location")
        end

        # [order, its address]. The order's WAIT starts here.
        def order(identifiers)
            answer = post(@directory.fetch("newOrder"), { identifiers: })
            @deadline = Time.now + WAIT
            [JSON.parse(answer.body), answer.fetch("location")]
        end

        def fetch(url) = JSON.parse(post(url, nil).body)

        # The authorization or order at `url`, polled until its status is
        # no longer one of `waiting`, within the one WAIT of the order.
        def settle(url, waiting)
            loop do
                answer = post(url, nil)
                body = JSON.parse(answer.body)
                return body unless waiting.include?(body["status"])
                raise Refused, "#{url} still #{body["status"]}" if
                    Time.now > @deadline

                sleep(pause(answer))
            end
        end

        # Retry-After in seconds, a second when it says nothing usable.
        def pause(answer)
            Integer(answer["retry-after"].to_s, exception: false) || 1
        end

        # Sends the request, waits for the certificate, returns it as PEM.
        def finish(order, url, csr)
            post(order.fetch("finalize"), { csr: ACME.b64(csr.to_der) })
            done = settle(url, %w[pending ready processing])
            raise Refused, ACME.problem(done["error"]) unless
                done["status"] == "valid"

            post(done.fetch("certificate"), nil).body
        end

        def thumbprint
            ACME.b64(OpenSSL::Digest::SHA256.digest(JSON.generate(jwk)))
        end

        # nil payload: a POST-as-GET, which reads a resource.
        def post(url, payload, jwk: false)
            RETRIES.times do
                answer = signed_post(url, payload, jwk)
                @nonce = answer["replay-nonce"]
                next if bad_nonce?(answer)
                return answer if answer.is_a?(Net::HTTPSuccess)

                raise Refused, ACME.problem(JSON.parse(answer.body))
            end
            raise Refused, "the authority refused #{RETRIES} nonces"
        end

        private

        def connect(uri, store)
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl      = true
            http.cert_store   = store
            http.open_timeout = http.read_timeout = 30
            http.start
        end

        def get(url) = @http.request(Net::HTTP::Get.new(URI(url)))

        def nonce
            @nonce || @http.request(
                Net::HTTP::Head.new(URI(@directory.fetch("newNonce")))
            )["replay-nonce"]
        end

        def bad_nonce?(answer)
            answer.code == "400" &&
                answer.body.include?("urn:ietf:params:acme:error:badNonce")
        end

        def signed_post(url, payload, use_jwk)
            request = Net::HTTP::Post.new(URI(url))
            request["content-type"] = "application/jose+json"
            request.body = jws(url, payload, use_jwk)
            @http.request(request)
        end

        def jws(url, payload, use_jwk)
            header = { alg: "ES256", nonce:, url: }
            use_jwk ? header[:jwk] = jwk : header[:kid] = @kid
            guarded = ACME.b64(JSON.generate(header))
            body = payload.nil? ? "" : ACME.b64(JSON.generate(payload))
            signature = @key.sign("SHA256", "#{guarded}.#{body}")
            JSON.generate(protected: guarded, payload: body,
                          signature: ACME.b64(raw(signature)))
        end

        # ES256 is the two 32-byte halves r and s, not OpenSSL's DER.
        def raw(der)
            OpenSSL::ASN1.decode(der).value
                         .map { it.value.to_s(2).rjust(32, "\0") }.join
        end

        # Members in the order RFC 7638 hashes them, which is also the
        # alphabetical one JSON.generate keeps.
        def jwk
            point = @key.public_key.to_octet_string(:uncompressed)
            { crv: "P-256", kty: "EC",
              x: ACME.b64(point[1, 32]), y: ACME.b64(point[33, 32]) }
        end
    end

    # Answering every authorization of an order, by the method the
    # settings name, and taking the answers down again whatever happens.
    module Challenge
        # One authorization still to win: where it is, the challenge
        # chosen, the name it is for, and the answer.
        Task = Struct.new(:url, :challenge, :identifier, :answer)

        # A token names a file, so an authority's token that is not
        # base64url (RFC 8555, 8.3) is refused before it reaches the disk.
        TOKEN = /\A[A-Za-z0-9_-]{1,128}\z/

        module_function

        def answer(session, tls, urls)
            tasks = pending(session, urls, tls[:challenge].to_s)
            return if tasks.empty?

            # Every check is started before any is waited for.
            serve(tls, tasks) do
                tasks.map { it.challenge["url"] }.each { session.post(it, {}) }
                tasks.each { settled!(session, it) }
            end
        end

        def pending(session, urls, method)
            thumbprint = session.thumbprint
            urls.map { [it, session.fetch(it)] }
                .reject { |_, authz| authz["status"] == "valid" }
                .map { |url, authz| task(url, authz, method, thumbprint) }
        end

        def task(url, authz, method, thumbprint)
            name = authz.dig("identifier", "value")
            found = authz["challenges"].find { it["type"] == method } or
                raise Refused, "#{name}: the authority offers no #{method}"
            raise Refused, "#{name}: the authority's token is malformed" unless
                found["token"].to_s.match?(TOKEN)

            Task.new(url, found, authz["identifier"],
                     "#{found["token"]}.#{thumbprint}")
        end

        def settled!(session, task)
            authz = session.settle(task.url, %w[pending])
            return if authz["status"] == "valid"

            failed = authz["challenges"].find { it["error"] }
            raise Refused, "#{task.identifier["value"]}: " \
                           "#{ACME.problem(failed&.dig("error"))}"
        end

        def serve(tls, tasks, &)
            return Tokens.around(tasks, &) if tls[:challenge].to_s == "http-01"

            Responder.around(tls.fetch(:port, 443), tasks, &)
        end
    end

    # http-01: one file per token, which tls_challenge_routes.rb serves,
    # removed once the authority has looked.
    module Tokens
        module_function

        def around(tasks)
            FileUtils.mkdir_p(CHALLENGES, mode: 0o700)
            files = tasks.map do |task|
                file = File.join(CHALLENGES, task.challenge["token"])
                File.write(file, task.answer, perm: 0o600)
                file
            end
            yield
        ensure
            files&.each { FileUtils.rm_f(it) }
        end
    end

    # tls-alpn-01: a TLS server for the length of the check, presenting
    # for each name a self-signed certificate that carries the hash of
    # its key authorization (RFC 8737), and to nobody who does not ask for
    # "acme-tls/1".
    class Responder
        PROTOCOL = "acme-tls/1"
        # The protocol, when the client offers it; nothing otherwise,
        # which ends the handshake.
        SELECT = ->(offered) { offered.find { it == PROTOCOL } }

        def self.around(port, tasks)
            responder = new(port, tasks)
            yield
        ensure
            responder&.stop
        end

        def initialize(port, tasks)
            holder = held(port)
            raise Unanswerable, in_use(port, " on #{holder}") if holder

            @contexts = contexts(tasks)
            @servers = listen(port)
            @thread  = Thread.new { Socket.accept_loop(@servers) { serve(it) } }
        rescue Errno::EADDRINUSE
            raise Unanswerable, in_use(port)
        rescue Errno::EACCES
            raise Unanswerable, "port #{port} needs privileges this user lacks"
        end

        def stop
            @thread.kill
            @servers.each(&:close)
        end

        private

        def in_use(port, where = "")
            "port #{port} is in use#{where} -- tls-alpn-01 needs it for " \
                "the check: stop the service first"
        end

        # The first of this machine's addresses where something answers
        # on the port, or nil. A server bound to one address does not
        # stop the wildcard bind below, which the system allows beside
        # it, and it would still be the one handed the checks for that
        # address. Asked rather than bound without SO_REUSEADDR, which
        # would also refuse the port while the connections of a server
        # just stopped are closing.
        def held(port)
            Socket.ip_address_list.map(&:ip_address)
                  .find { answers?(it, port) }
        end

        def answers?(address, port)
            Socket.tcp(address, port, connect_timeout: 1).close
            true
        rescue SystemCallError, SocketError, IO::TimeoutError
            false
        end

        def contexts(tasks)
            tasks.to_h do |task|
                [server_name(task.identifier),
                 context(task.identifier, task.answer)]
            end
        end

        # Both families, each bound on its own so that a port held in one
        # of them is refused: a responder answering on IPv6 alone while
        # the server keeps IPv4 sends half the checks to the server. A
        # family the host lacks is skipped. The IPv6 socket is made
        # IPv6-only (Addrinfo#listen does it), or on a system where it
        # takes IPv4 too by default it collides with the first.
        def listen(port)
            servers = []
            %w[0.0.0.0 ::].each do |any|
                servers << Addrinfo.tcp(any, port).listen
            rescue Errno::EADDRNOTAVAIL, Errno::EAFNOSUPPORT, SocketError
                next
            end
            servers
        rescue SystemCallError
            servers.each(&:close)
            raise
        end

        # An address is asked for by its reverse name (RFC 8738).
        def server_name(identifier)
            value = identifier["value"]
            identifier["type"] == "ip" ? IPAddr.new(value).reverse : value
        end

        def serve(socket)
            Thread.new do
                tls = OpenSSL::SSL::SSLSocket.new(socket, selector)
                tls.accept
            rescue StandardError
                nil
            ensure
                tls&.close
                socket.close
            end
        end

        # Chooses the certificate by the name asked for; a name that has
        # none ends the handshake.
        def selector
            context = OpenSSL::SSL::SSLContext.new
            context.servername_cb = ->((_, name)) { @contexts.fetch(name) }
            context
        end

        def context(identifier, authorization)
            key = OpenSSL::PKey::EC.generate("prime256v1")
            context = OpenSSL::SSL::SSLContext.new
            context.cert = Proof.certificate(identifier, authorization, key)
            context.key  = key
            context.alpn_protocols = [PROTOCOL]
            context.alpn_select_cb = SELECT
            context
        end
    end

    # The certificate a tls-alpn-01 check expects to be shown: one per
    # name, self-signed, worthless for anything else.
    module Proof
        IDENTIFIER = "1.3.6.1.5.5.7.1.31" # id-pe-acmeIdentifier

        module_function

        # The name alone, critical since the subject is empty, and the
        # hash of the answer in the extension RFC 8737 defines for it.
        def certificate(identifier, authorization, key)
            cert = self_signed(key)
            factory = OpenSSL::X509::ExtensionFactory.new(cert, cert)
            name = alternative(identifier)
            cert.add_extension(
                factory.create_extension("subjectAltName", name, true)
            )
            cert.add_extension(validation(authorization))
            cert.sign(key, "SHA256")
        end

        def alternative(identifier)
            name = identifier["value"]
            identifier["type"] == "ip" ? "IP:#{name}" : "DNS:#{name}"
        end

        def validation(authorization)
            digest = OpenSSL::Digest::SHA256.digest(authorization)
            OpenSSL::X509::Extension.new(
                IDENTIFIER, OpenSSL::ASN1::OctetString(digest).to_der, true
            )
        end

        # Lives an hour: long enough for any check, short enough to be
        # worthless afterwards.
        def self_signed(key)
            cert = OpenSSL::X509::Certificate.new
            cert.version    = 2
            cert.serial     = OpenSSL::BN.rand(127)
            cert.subject    = cert.issuer = OpenSSL::X509::Name.new([])
            cert.public_key = key
            cert.not_before = Time.now - 60
            cert.not_after  = Time.now + 3600
            cert
        end
    end
end
