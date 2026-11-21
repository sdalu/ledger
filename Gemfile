source "https://rubygems.org"
ruby ">= 3.4"

gem "sinatra", "~> 4.2"
gem "puma",    "~> 8.0"
gem "erubi",   "~> 1.13"
gem "rake",    "~> 13.0"

# the journal: every ledger and the sign-in state in one SQLite file
gem "sequel",   "~> 5.100"
gem "sqlite3",  "~> 2.0"

# sign-in: invitations, password and passkeys, kept in the journal
gem "sesam",    github: "sdalu/sesam", tag: "v0.3.0"
gem "webauthn", "~> 3.4"

group :development, :test do
    gem "minitest",  "~> 6.0"
    gem "rack-test", "~> 2.2"
    gem "rubocop",   "~> 1.81", require: false
end
