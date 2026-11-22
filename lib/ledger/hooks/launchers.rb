# frozen_string_literal: true

module Ledger
    module Hooks
        # The words that only start another program (nice, timeout, env,
        # sudo, ...) and the shell keywords that open a command (if, then,
        # do, ...): where the program word of a segment is, past them and
        # past their own options.
        #
        #     Launchers.program_at(%w[nice -n 19 sqlite3 j.db])  # => 3
        #     Launchers.program_at(%w[env -S x sqlite3 j.db])    # => nil
        #
        # nil means an option the table does not know, so the program
        # cannot be told; the caller decides what that costs.
        module Launchers
            Spec = Data.define(:flags, :args, :long_flags, :long_args,
                               :positional, :number)

            BLANK = { flags: "", args: "", long_flags: [], long_args: [],
                      positional: 0, number: false }.freeze

            def self.spec(**given) = Spec.new(**BLANK, **given)

            SPECS = {
                "nice" => spec(args: "n", long_args: %w[--adjustment],
                               number: true),
                "timeout" => spec(flags: "fpv", args: "sk",
                                  long_flags: %w[--foreground --verbose
                                                 --preserve-status],
                                  long_args: %w[--signal --kill-after],
                                  positional: 1),
                "env" => spec(flags: "i0v", args: "uC",
                              long_flags: %w[--ignore-environment --null
                                             --debug],
                              long_args: %w[--unset --chdir]),
                "sudo" => spec(flags: "AbEeHKklnPSBvV", args: "ughpCDRTrtU",
                               long_flags: %w[--preserve-env --background
                                              --non-interactive
                                              --reset-timestamp],
                               long_args: %w[--user --group --host --prompt
                                             --chdir --chroot]),
                "command" => spec(flags: "p"),
                "exec" => spec(flags: "cl", args: "a"),
                "nohup" => spec,
                "time" => spec(flags: "apv", args: "fo"),
                "low-priority" => spec(flags: "v")
            }.freeze
            KEYWORDS = %w[if then else elif do while until ! {].freeze
            ASSIGNMENT = /\A\w+=/

            # -> the index of the program word in WORDS (WORDS.size when
            # there is none), or nil when a launcher's option is unknown.
            def self.program_at(words)
                at = 0
                while (word = words[at])
                    spec = SPECS[File.basename(word)]
                    return at unless spec || skipped?(word)
                    at = spec ? past_options(spec, words, at + 1) : at + 1
                    return nil unless at
                end
                at
            end

            def self.skipped?(word)
                ASSIGNMENT.match?(word) || KEYWORDS.include?(word)
            end

            # -> the index after the options (and positional words) of a
            # launcher whose first argument is at AT; nil for an option
            # the spec does not list.
            def self.past_options(spec, words, at)
                while (word = words[at])&.match?(/\A-./)
                    return at + 1 if word == "--"
                    at = option_end(spec, words, at)
                    return nil unless at
                end
                at + spec.positional
            end

            def self.option_end(spec, words, at)
                word = words[at]
                return at + 1 if spec.number && word.match?(/\A-\d+\z/)
                return long_end(spec, word, at) if word.start_with?("--")
                short_end(spec, word, at)
            end

            def self.long_end(spec, word, at)
                name, value = word.split("=", 2)
                if spec.long_flags.include?(name)
                    at + 1
                elsif spec.long_args.include?(name)
                    at + (value ? 1 : 2)
                end
            end

            # A cluster of short options: flags, then at most one option
            # taking a value (attached, or the next word).
            def self.short_end(spec, word, at)
                word[1..].each_char.with_index(1) do |char, index|
                    next if spec.flags.include?(char)
                    return nil unless spec.args.include?(char)
                    return at + (index == word.size - 1 ? 2 : 1)
                end
                at + 1
            end
        end
    end
end
