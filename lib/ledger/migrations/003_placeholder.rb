# frozen_string_literal: true

# A placeholder for migration 003, which another branch brings: the
# integer migrator refuses a gap before 005_waker. Dropped at the merge,
# where that branch's 003 takes its place.

Sequel.migration do
    change do
        # Nothing: the real 003 is another branch's.
    end
end
