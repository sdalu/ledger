# frozen_string_literal: true

# The viewer's pages, drawn from a ledger's dump: plain objects, no
# Sinatra, so that a route and a comparison against the Python viewer
# call the same code.
require_relative "render/renderer"
