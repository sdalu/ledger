# frozen_string_literal: true

# A placeholder for migration 004, which another branch brings: the
# integer migrator refuses a gap before 005_waker. Dropped at the merge,
# where that branch's 004 takes its place.

Sequel.migration do
    change do
        # Nothing: the real 004 is another branch's.
    end
end
