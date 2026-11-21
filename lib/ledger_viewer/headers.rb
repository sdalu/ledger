# frozen_string_literal: true

module LedgerViewer
    # What the viewer sends with what it serves: its pages carry
    # a policy that lets them run their own script and style, post to
    # themselves and frame a mockup of the same origin and nothing else;
    # a mockup carries one that puts it in an opaque origin, with no way
    # to reach the viewer's pages or its POST, even when opened on its
    # own.
    module Headers
        PAGE_CSP = "default-src 'none'; style-src 'unsafe-inline'; " \
                   "script-src 'unsafe-inline'; connect-src 'self'; " \
                   "form-action 'self'; img-src 'self'; frame-src 'self'"
        MOCKUP_CSP = "sandbox allow-scripts; default-src 'self' data: " \
                     "'unsafe-inline'; connect-src 'none'; " \
                     "form-action 'none'; frame-src 'none'; base-uri 'none'"

        PAGE = { "Cache-Control" => "no-store",
                 "X-Content-Type-Options" => "nosniff",
                 "Content-Security-Policy" => PAGE_CSP }.freeze
        EVENTS = { "Cache-Control" => "no-store",
                   "X-Content-Type-Options" => "nosniff",
                   "Connection" => "close" }.freeze
        MOCKUP = PAGE.merge("Content-Security-Policy" => MOCKUP_CSP).freeze
    end
end
