# frozen_string_literal: true

require "json"

module LedgerViewer
    # json.dumps(value, ensure_ascii=False) as Python writes it, with its
    # ", " and ": " separators: the line the Python viewer appends to an
    # inbox, which the engine reads and the page shows back, byte for
    # byte.
    module PyJson
        def self.dump(value)
            case value
            when Hash then "{#{value.map { pair(*it) }.join(", ")}}"
            when Array then "[#{value.map { dump(it) }.join(", ")}]"
            when nil then "null"
            else JSON.generate(value)
            end
        end

        def self.pair(key, value) = "#{dump(key)}: #{dump(value)}"
    end
end
