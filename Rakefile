# -*- ruby -*-
# frozen_string_literal: true

# The project's gate is `rake`: it runs the suite and the style check
# and exits nonzero if either fails, so "the gate passed" is one
# observable fact rather than two commands somebody has to remember.

# help.rake enumerates the described tasks, which rake only records when
# told to before any task is defined; the Rakefile loads before rakelib/.
Rake::TaskManager.record_task_metadata = true

# The umbrella requires its parts from the load path; the pre-flight
# requires the umbrella by file name, which leaves lib/ off it.
$LOAD_PATH.unshift File.expand_path("lib", __dir__)

# tls.rake names the certificate's directory from the settings when it
# is loaded.
require "ledger_viewer"

require "rake/clean"
require "rake/testtask"

# What a run writes: the pidfile config/puma.rb puts in tmp/.
CLEAN.include("tmp")

Rake::TestTask.new do |task|
    task.libs << "lib" << "test"
    task.pattern = "test/**/*_test.rb"
    task.warning = false
end

# The house rules live outside the repository, so their path is resolved
# here at run time; this project's deltas (.rubocop.local.yml) are
# layered on top, house first, so a delta can only relax a rule in force.
RUBOCOP_HOUSE = File.expand_path("~/.claude/skills/ruby/scripts/rubocop.yml")

# Rubocop on PATHS under the house rules and this project's deltas.
def rubocop_run(paths)
    unless File.exist?(RUBOCOP_HOUSE)
        warn "rubocop: house rules not found at #{RUBOCOP_HOUSE} -- skipped"
        return
    end
    require "tmpdir"
    Dir.mktmpdir do |dir|
        merged = File.join(dir, "rubocop.yml")
        File.write(merged, rubocop_config)
        sh("rubocop", "-c", merged, *paths, verbose: false)
    end
end

def rubocop_config
    <<~YAML
        inherit_from:
          - #{RUBOCOP_HOUSE}
          - #{File.expand_path(".rubocop.local.yml", __dir__)}
    YAML
end

desc "Style check: the house Ruby rules plus this project's deltas"
task :rubocop do
    rubocop_run(%w[lib test rakelib config Rakefile config.ru])
end

task default: %i[test rubocop]
